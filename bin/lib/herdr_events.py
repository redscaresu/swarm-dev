"""herdr_events.py <socket> <pane> <timeout-ms> — wait on herdr's event stream for <pane>'s agent.

Subscribes (events.subscribe) to the pane's pane.agent_status_changed and to pane.closed and
pane.exited, then reads its agent (agent.get), so a state it already holds counts. Prints the first
of idle, blocked or done, or gone when the pane closes, exits or is not found, and exits 0. Exits 3
at the timeout (TIMED_OUT, a code Python never exits with by itself). On anything else (no socket, a
refused request, the stream ended, a reply it cannot read) it prints the milliseconds left of
<timeout-ms> and exits 2; any other exit, such as 1 for an uncaught error, means the same: the
caller polls.
"""
import json, socket, sys, time
from contextlib import closing

SETTLED = ("idle", "blocked", "done")
# DONE: what ends the wait.
DONE = SETTLED + ("gone",)
# REPLY_S: how long herdr has to accept the connection and answer a request.
REPLY_S = 5
# GONE: agent.get's error for a pane herdr cannot find; SUB_GONE: events.subscribe's, for a pane that
# closed before the subscription.
GONE = "agent_not_found"
SUB_GONE = "pane_not_found"
# RECHECK_S: how often agent.get is read again while it does not show a settle event (it can lag one).
RECHECK_S = 1
# TIMED_OUT: the exit code at the timeout.
TIMED_OUT = 3


def left(end):
    return max(end - time.monotonic(), 0.001)


class Conn:
    """A connection to herdr's socket, read a line at a time; each read ends by its end time, however
    slowly herdr sends the line."""

    def __init__(self, path, end):
        self.s, self.buf = socket.socket(socket.AF_UNIX), b""
        try:
            self.s.settimeout(left(end))
            self.s.connect(path)
        except BaseException:
            self.s.close()
            raise

    def close(self):
        self.s.close()

    def read(self, end):
        while b"\n" not in self.buf:
            self.s.settimeout(left(end))
            chunk = self.s.recv(65536)
            if not chunk:
                raise EOFError("herdr closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line


def request(path, req, deadline):
    """A new connection with <req> sent on it, and herdr's reply, all within REPLY_S and by <deadline>."""
    end = min(time.monotonic() + REPLY_S, deadline)
    c = Conn(path, end)
    try:
        c.s.settimeout(left(end))
        c.s.sendall((json.dumps(req) + "\n").encode())
        return c, json.loads(c.read(end))
    except BaseException:
        c.close()
        raise


def status(path, pane, deadline):
    """The agent's status now (agent.get), or gone when herdr finds no pane."""
    c, reply = request(path, {"id": "swarm-get", "method": "agent.get", "params": {"target": pane}}, deadline)
    c.close()
    if reply.get("error", {}).get("code") == GONE:
        return "gone"
    return reply["result"]["agent"]["agent_status"]


def by_deadline(deadline, late, fn, *args):
    """fn(*args), or <late> when the deadline cuts herdr's answer off. A timeout before the deadline is
    herdr too slow to answer, not the wait over, so it is raised: the caller polls instead."""
    try:
        return fn(*args)
    except socket.timeout:
        if time.monotonic() < deadline:
            raise
        return late


def watch(path, pane, deadline):
    subs = [{"type": "pane.agent_status_changed", "pane_id": pane}, {"type": "pane.closed"}, {"type": "pane.exited"}]
    stream, ack = request(path, {"id": "swarm-wait", "method": "events.subscribe", "params": {"subscriptions": subs}}, deadline)
    with closing(stream):
        if ack.get("error", {}).get("code") == SUB_GONE:
            return "gone"
        if "result" not in ack:
            raise OSError(ack.get("error"))
        # said: the last settle event, while agent.get does not show it. An event queued before a read
        # may be stale (idle, then working again), so agent.get decides, read again every RECHECK_S
        # until it agrees, a later event says otherwise, or the deadline passes, when the event's
        # word stands if agent.get has not answered.
        said = None

        def confirm():
            return by_deadline(deadline, said, status, path, pane, deadline)

        now = status(path, pane, deadline)
        # Other panes' close and exit events keep the stream busy, so the deadline is checked, not only
        # the read's timeout.
        while now not in DONE and time.monotonic() < deadline:
            try:
                line = stream.read(min(deadline, time.monotonic() + RECHECK_S) if said else deadline)
            except socket.timeout:
                if not said or time.monotonic() >= deadline:
                    raise
                now = confirm()
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue   # a blank line (herdr's keepalive) or one that is not JSON
            data = ev.get("data") if isinstance(ev, dict) else None
            if not isinstance(data, dict) or data.get("pane_id") != pane:
                continue   # another pane's event, or a line that is none (a keepalive, a late reply)
            kind = str(ev.get("event", ""))   # lifecycle events come as pane_closed, subscription ones as pane.<x>
            kind = "pane." + kind[5:] if kind.startswith("pane_") else kind
            if kind in ("pane.closed", "pane.exited"):
                return "gone"
            if kind == "pane.agent_status_changed":
                said = data.get("agent_status") if data.get("agent_status") in SETTLED else None
                if said:
                    now = confirm()
        return now if now in DONE else None


def wait(path, pane, deadline):
    return by_deadline(deadline, None, watch, path, pane, deadline)


if __name__ == "__main__":
    deadline = time.monotonic() + int(sys.argv[3]) / 1000   # the requests count against the timeout
    try:
        got = wait(sys.argv[1], sys.argv[2], deadline)
    except Exception:   # no stream to trust, so the caller polls for what is left
        print(int(left(deadline) * 1000))
        sys.exit(2)
    if got is None:
        sys.exit(TIMED_OUT)
    print(got)

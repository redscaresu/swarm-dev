"""herdr_events.py <socket> <pane> <timeout-ms> — wait on herdr's event stream for <pane>'s agent.

Subscribes (events.subscribe) to the pane's pane.agent_status_changed and to pane.closed and
pane.exited, then reads its agent (agent.get), so a state it already holds counts. Prints the first
of idle, blocked or done, or gone when the pane closes, exits or is not found, and exits 0. Exits 1
at the timeout. On anything else (no socket, a refused request, the stream ended, a reply it cannot
read) it prints the milliseconds left of <timeout-ms> and exits 2: the caller polls for that long.
"""
import json, socket, sys, time
from contextlib import closing

SETTLED = ("idle", "blocked", "done")
# REPLY_S: how long herdr has to accept the connection and answer a request.
REPLY_S = 5
# GONE: the error codes herdr answers for a pane it cannot find (agent.get's, events.subscribe's).
GONE = ("agent_not_found", "pane_not_found")


def left(end):
    return max(end - time.monotonic(), 0.001)


class Conn:
    """A connection to herdr's socket, read a JSON line at a time; each read ends by its end time,
    however slowly herdr sends the line."""

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
        return json.loads(line)


def request(path, req, deadline):
    """A new connection with <req> sent on it, and herdr's reply, all within REPLY_S and by <deadline>."""
    end = min(time.monotonic() + REPLY_S, deadline)
    c = Conn(path, end)
    try:
        c.s.settimeout(left(end))
        c.s.sendall((json.dumps(req) + "\n").encode())
        return c, c.read(end)
    except BaseException:
        c.close()
        raise


def status(path, pane, deadline):
    """The agent's status now (agent.get), or gone when herdr finds no pane."""
    c, reply = request(path, {"id": "swarm-get", "method": "agent.get", "params": {"target": pane}}, deadline)
    c.close()
    if reply.get("error", {}).get("code") in GONE:
        return "gone"
    return reply["result"]["agent"]["agent_status"]


def watch(path, pane, deadline):
    subs = [{"type": "pane.agent_status_changed", "pane_id": pane}, {"type": "pane.closed"}, {"type": "pane.exited"}]
    stream, ack = request(path, {"id": "swarm-wait", "method": "events.subscribe", "params": {"subscriptions": subs}}, deadline)
    with closing(stream):
        if "result" not in ack:
            raise OSError(ack.get("error"))
        now = status(path, pane, deadline)
        # Other panes' close and exit events keep the stream busy, so the deadline is checked, not only
        # the read's timeout.
        while now not in SETTLED + ("gone",) and time.monotonic() < deadline:
            ev = stream.read(deadline)
            data = ev.get("data") if isinstance(ev, dict) else None
            if not isinstance(data, dict) or data.get("pane_id") != pane:
                continue   # another pane's event, or a line that is none (a keepalive, a late reply)
            kind = str(ev.get("event", ""))   # lifecycle events come as pane_closed, subscription ones as pane.<x>
            kind = "pane." + kind[5:] if kind.startswith("pane_") else kind
            if kind in ("pane.closed", "pane.exited"):
                return "gone"
            # An event queued before the read above may be stale (idle, then working again), so it only
            # sends the wait to read the agent again.
            if kind == "pane.agent_status_changed" and data.get("agent_status") in SETTLED:
                now = status(path, pane, deadline)
        return now if now in SETTLED + ("gone",) else None


def wait(path, pane, deadline):
    try:
        return watch(path, pane, deadline)
    except socket.timeout:
        if time.monotonic() < deadline:
            raise   # herdr is slow to answer, not the wait over: poll instead
        return None


if __name__ == "__main__":
    deadline = time.monotonic() + int(sys.argv[3]) / 1000   # the requests count against the timeout
    try:
        got = wait(sys.argv[1], sys.argv[2], deadline)
    except Exception:   # no stream to trust, so the caller polls for what is left
        print(int(left(deadline) * 1000))
        sys.exit(2)
    if got is None:
        sys.exit(1)
    print(got)

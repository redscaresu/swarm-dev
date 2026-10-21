"""herdr_events.py <socket> <pane> <timeout-ms> — wait on herdr's event stream for <pane>'s agent.

Subscribes (events.subscribe) to the pane's pane.agent_status_changed and to pane.closed and
pane.exited, then reads its agent once (agent.get), so a state it already holds counts. Prints the
first of idle, blocked or done, or gone when the pane closes or exits, and exits 0. Exits 1 at the
timeout, and 2 on anything else (no socket, a refused request, the stream ended, a reply it cannot
read): the caller polls as before.
"""
import json, socket, sys, time

SETTLED = ("idle", "blocked", "done")
# REPLY_S: how long herdr has to accept the connection and answer a request.
REPLY_S = 5


def left(deadline):
    return max(deadline - time.monotonic(), 0.001)


def request(path, req, deadline):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(min(REPLY_S, left(deadline)))
    s.connect(path)
    s.sendall((json.dumps(req) + "\n").encode())
    f = s.makefile()
    return s, f, json.loads(f.readline())


def wait(path, pane, timeout_ms):
    deadline = time.monotonic() + timeout_ms / 1000   # the requests below count against the timeout
    subs = [{"type": "pane.agent_status_changed", "pane_id": pane}, {"type": "pane.closed"}, {"type": "pane.exited"}]
    try:
        s, f, ack = request(path, {"id": "swarm-wait", "method": "events.subscribe", "params": {"subscriptions": subs}}, deadline)
        if "result" not in ack:
            raise OSError(ack.get("error"))
        g, _, now = request(path, {"id": "swarm-get", "method": "agent.get", "params": {"target": pane}}, deadline)
        g.close()
    except socket.timeout:
        if time.monotonic() < deadline:
            raise   # herdr is slow to answer, not the wait over: poll instead
        return None
    # The pane was there for the subscription and is not now: it closed in between.
    if now.get("error", {}).get("code") == "pane_not_found":
        return "gone"
    if now["result"]["agent"]["agent_status"] in SETTLED:
        return now["result"]["agent"]["agent_status"]
    # Other panes' close and exit events keep the stream busy, so the deadline is checked, not only
    # the read's timeout.
    while time.monotonic() < deadline:
        s.settimeout(left(deadline))
        try:
            line = f.readline()
        except socket.timeout:
            return None
        if not line:
            raise EOFError("herdr closed the event stream")
        ev = json.loads(line)
        data = ev["data"]
        if data.get("pane_id") != pane:
            continue
        kind = ev["event"]   # lifecycle events come as pane_closed, subscription ones as pane.<x>
        kind = "pane." + kind[5:] if kind.startswith("pane_") else kind
        if kind in ("pane.closed", "pane.exited"):
            return "gone"
        if kind == "pane.agent_status_changed" and data.get("agent_status") in SETTLED:
            return data["agent_status"]


if __name__ == "__main__":
    try:
        status = wait(sys.argv[1], sys.argv[2], int(sys.argv[3]))
    except Exception:   # no stream to trust, so the caller polls
        sys.exit(2)
    if status is None:
        sys.exit(1)
    print(status)

#!/usr/bin/env bash
# herdr_events_test.sh — wait on an agent herdr answers for (no Claude session) listens to herdr's
# event stream at HERDR_SOCKET_PATH: a fake socket server stands in for herdr's, and a herdr stub
# on PATH logs every CLI call, so a wait that polled shows `agent wait` in the log.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# A Unix socket path has a short limit (104 bytes on macOS), so the socket gets a short dir of its own.
sock_dir="$(mktemp -d /tmp/swarm-ev.XXXXXX)"
SOCK="${sock_dir}/h.sock"
server=""
trap '[[ -z "${server}" ]] || kill "${server}" 2>/dev/null; rm -rf "${ROOT}" "${sock_dir}"' EXIT
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: logs every call; agent cx works in pane w:7; agent wait (the poll) says idle.
cat > "${ROOT}/herdr" <<EOF
#!/bin/sh
echo "\$*" >> "${ROOT}/herdr.log"
case "\$1 \$2" in
  "agent list") echo '{"result":{"agents":[{"name":"cx","agent_status":"working","pane_id":"w:7"}]}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
esac
EOF
chmod +x "${ROOT}/herdr"

# The fake herdr socket: newline-delimited JSON. agent.get says the agent works, or with mode now
# that it is blocked. events.subscribe is acknowledged, then, a moment later, gets another pane's
# event and then mode's: blocked (pane.agent_status_changed) or closed (pane_closed, the lifecycle
# envelope). Mode vanish has agent.get find no pane: it closed after the subscription. Mode refuse
# answers the subscription with an error, as herdr does for an unknown pane.
cat > "${ROOT}/server.py" <<'EOF'
import json, os, socketserver, sys, time
path, mode = sys.argv[1], sys.argv[2]
class H(socketserver.StreamRequestHandler):
    def handle(self):
        req = json.loads(self.rfile.readline())
        out = lambda o: (self.wfile.write((json.dumps(o) + "\n").encode()), self.wfile.flush())
        if req["method"] == "agent.get" and mode == "vanish":
            out({"id": req["id"], "error": {"code": "pane_not_found", "message": "pane w:7 not found"}})
            return
        if req["method"] == "agent.get":
            out({"id": req["id"], "result": {"agent": {"pane_id": "w:7", "agent_status": "blocked" if mode == "now" else "working"}}})
            return
        if mode == "refuse":
            out({"id": req["id"], "error": {"code": "pane_not_found", "message": "pane w:7 not found"}})
            return
        out({"id": req["id"], "result": {"type": "subscription_started"}})
        time.sleep(0.3)
        out({"event": "pane.agent_status_changed", "data": {"pane_id": "w:8", "workspace_id": "w", "agent_status": "idle"}})
        if mode == "blocked":
            out({"event": "pane.agent_status_changed", "data": {"pane_id": "w:7", "workspace_id": "w", "agent_status": "blocked"}})
        elif mode == "closed":
            out({"event": "pane_closed", "data": {"type": "pane_closed", "pane_id": "w:7", "workspace_id": "w"}})
        time.sleep(30)
socketserver.ThreadingUnixStreamServer.daemon_threads = True
socketserver.ThreadingUnixStreamServer.handle_error = lambda *a: None   # a client that hung up first
socketserver.ThreadingUnixStreamServer(path, H).serve_forever()
EOF
serve() { # <mode> — (re)start the fake socket in <mode>
  [[ -z "${server}" ]] || { kill "${server}" 2>/dev/null; wait "${server}" 2>/dev/null || true; }
  rm -f "${SOCK}"; python3 "${ROOT}/server.py" "${SOCK}" "$1" & server=$!
  local i; for ((i = 0; i < 50; i++)); do [[ -S "${SOCK}" ]] && return; sleep 0.1; done
  echo "the fake socket never came up" >&2; exit 1
}

p="${ROOT}/proj"; mkdir -p "${p}/.claude/swarm" "${p}/.swarm/state"; : > "${p}/.claude/swarm/config"
echo "w:7 cx" > "${p}/.swarm/state/wait-cx"   # this project's agent cx, in a pane it recorded
# wait_cx [<socket>] — "<stdout>|<polls>|<seconds>": wait on cx (a minute's slice, two minutes in
# all), with HERDR_SOCKET_PATH set to <socket> or unset.
wait_cx() {
  local t0=${SECONDS} out
  : > "${ROOT}/herdr.log"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_SOCKET_PATH ${1:+HERDR_SOCKET_PATH="$1"} HERDR_ENV=1 \
    PATH="${ROOT}:${PATH}" bash "${SWARM}" wait cx 120000 2>/dev/null)" || true
  echo "${out}|$(grep -c '^agent wait' "${ROOT}/herdr.log" || true)|$((SECONDS - t0))"
}
quick() { local s="${1##*|}"; [[ ${s} -lt 10 ]] && echo "${1%|*}" || echo "${1%|*} after ${s}s"; }

serve blocked
check "an agent herdr reports blocked on the event stream: wait returns blocked at once, without a poll" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}")")"
serve closed
check "the agent's pane closes: wait returns gone at once, without a poll" "gone|0" "$(quick "$(wait_cx "${SOCK}")")"
serve now
check "an agent already blocked when wait subscribes: wait returns blocked, without a poll" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}")")"
# A stream that never runs dry (another pane's events, each there at once) still ends at the
# deadline: herdr_events.py's own wait, its requests stubbed, cut off by an alarm after 5 s.
cat > "${ROOT}/busy.py" <<'EOF'
import json, sys
sys.path.insert(0, sys.argv[1]); import herdr_events as h
class Stream:
    def settimeout(self, t): pass
    def close(self): pass
    def readline(self): return json.dumps({"event": "pane_closed", "data": {"pane_id": "w:8"}}) + "\n"
def request(path, req, deadline):
    if req["method"] == "events.subscribe":
        return Stream(), Stream(), {"result": {}}
    return Stream(), None, {"result": {"agent": {"agent_status": "working"}}}
h.request = request
print(h.wait("sock", "w:7", 200))
EOF
check "a stream busy with other panes' events still times out at the deadline" "None" \
  "$(perl -e 'alarm 5; exec @ARGV' python3 -I "${ROOT}/busy.py" "$(dirname "${SWARM}")/lib" 2>&1 || true)"
serve vanish
check "the pane closes between the subscription and the read of its agent: wait returns gone, without a poll" \
  "gone|0" "$(quick "$(wait_cx "${SOCK}")")"
serve refuse
check "a stream that refuses the subscription: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx "${SOCK}")")"
check "no socket: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx)")"
kill "${server}"; wait "${server}" 2>/dev/null || true; server=""   # its socket file stays behind
check "a socket nothing listens on any more: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx "${SOCK}")")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

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

# herdr: logs every call; agent cx works in pane w:7; agent wait (the poll) says idle. With
# ${ROOT}/garbled it answers with no JSON and exits 0; with ${ROOT}/slowfail its first call fails for
# real after 0.8 s, and later ones time out.
cat > "${ROOT}/herdr" <<EOF
#!/bin/sh
echo "\$*" >> "${ROOT}/herdr.log"
case "\$1 \$2" in
  "agent list") echo '{"result":{"agents":[{"name":"cx","agent_status":"working","pane_id":"w:7"}]}}' ;;
  "agent wait")
    if [ -f "${ROOT}/garbled" ]; then echo 'herdr: no JSON here'; exit 0; fi
    if [ -f "${ROOT}/slowfail" ]; then
      if [ "\$(grep -c '^agent wait' "${ROOT}/herdr.log")" -eq 1 ]; then
        sleep 0.8; echo '{"error":{"code":"internal","message":"herdr failed"}}' >&2; exit 1
      fi
      echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}' >&2; exit 1
    fi
    echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
esac
EOF
chmod +x "${ROOT}/herdr"

# The fake herdr socket: newline-delimited JSON. agent.get says the agent works, or with mode now
# that it is blocked. events.subscribe is acknowledged, then, a moment later, gets another pane's
# event and then mode's: blocked (pane.agent_status_changed, agent.get blocked from then on), closed
# (pane_closed, the lifecycle envelope), stale (an idle event from before agent.get, which still says
# working), noise (lines that are no event, then blocked), junk (a blank line and one that is not
# JSON, then blocked), lag (blocked, though the next agent.get still says working) or slowget
# (blocked, though no agent.get after the first answers), drop (the stream ends) or silent (nothing). Mode vanish has agent.get find no pane (herdr's agent_not_found): it closed after the
# subscription. Mode refuse answers the subscription with an error, as herdr does for an unknown
# pane. Mode dribble sends the subscription's reply a byte every tenth of a second.
cat > "${ROOT}/server.py" <<'EOF'
import json, os, socketserver, sys, time
path, mode = sys.argv[1], sys.argv[2]
agent = {"status": "blocked" if mode == "now" else "working", "lag": 0, "gets": 0}
class H(socketserver.StreamRequestHandler):
    def handle(self):
        req = json.loads(self.rfile.readline())
        out = lambda o: (self.wfile.write((json.dumps(o) + "\n").encode()), self.wfile.flush())
        if req["method"] == "agent.get" and mode == "vanish":
            out({"id": req["id"], "error": {"code": "agent_not_found", "message": "agent target w:7 not found"}})
            return
        if req["method"] == "agent.get":
            agent["gets"] += 1
            if mode == "slowget" and agent["gets"] > 1:
                time.sleep(30)
            if agent["lag"]:
                agent["lag"] -= 1
                out({"id": req["id"], "result": {"agent": {"pane_id": "w:7", "agent_status": "working"}}})
                return
            out({"id": req["id"], "result": {"agent": {"pane_id": "w:7", "agent_status": agent["status"]}}})
            return
        if mode == "refuse":
            out({"id": req["id"], "error": {"code": "pane_not_found", "message": "pane w:7 not found"}})
            return
        if mode == "dribble":
            for b in (json.dumps({"id": req["id"], "result": {"type": "subscription_started"}}) + "\n").encode():
                self.wfile.write(bytes([b])); self.wfile.flush(); time.sleep(0.1)
            return
        out({"id": req["id"], "result": {"type": "subscription_started"}})
        time.sleep(0.3)
        out({"event": "pane.agent_status_changed", "data": {"pane_id": "w:8", "workspace_id": "w", "agent_status": "idle"}})
        if mode == "drop":
            return
        if mode == "stale":
            out({"event": "pane.agent_status_changed", "data": {"pane_id": "w:7", "workspace_id": "w", "agent_status": "idle"}})
        if mode == "noise":
            out({"id": "late", "result": {}}); out({"event": "keepalive"}); out([])
        if mode == "junk":
            self.wfile.write(b"\nnot json\n")
        if mode in ("blocked", "noise", "junk", "lag", "slowget"):
            agent["status"], agent["lag"] = "blocked", 1 if mode == "lag" else 0
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
# wait_cx [<socket>] [<ms>] — "<stdout>|<polls>|<seconds>": wait on cx for <ms> (two minutes) in
# slices of SLICE ms (a minute), with HERDR_SOCKET_PATH set to <socket> or unset, and PRE, when set,
# first on PATH. Its exit code goes to ${ROOT}/rc.
wait_cx() {
  local t0=${SECONDS} out
  : > "${ROOT}/herdr.log"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_SOCKET_PATH ${1:+HERDR_SOCKET_PATH="$1"} HERDR_ENV=1 \
    SWARM_STALL_POLL_MS="${SLICE:-60000}" PATH="${PRE:+${PRE}:}${ROOT}:${PATH}" bash "${SWARM}" wait cx "${2:-120000}" 2>/dev/null)" \
    && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
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
    def close(self): pass
    def read(self, end): return json.dumps({"event": "pane_closed", "data": {"pane_id": "w:8"}})
def request(path, req, deadline):
    if req["method"] == "events.subscribe":
        return Stream(), {"result": {}}
    return Stream(), {"result": {"agent": {"agent_status": "working"}}}
h.request = request
print(h.wait("sock", "w:7", h.time.monotonic() + 0.2))
EOF
check "a stream busy with other panes' events still times out at the deadline" "None" \
  "$(perl -e 'alarm 5; exec @ARGV' python3 -I "${ROOT}/busy.py" "$(dirname "${SWARM}")/lib" 2>&1 || true)"
serve vanish
check "the pane closes between the subscription and the read of its agent: wait returns gone, without a poll" \
  "gone|0" "$(quick "$(wait_cx "${SOCK}")")"
serve stale
check "an idle event queued before wait read the agent, which works: wait does not return idle" \
  "|0" "$(quick "$(wait_cx "${SOCK}" 1500)")"
serve noise
check "stream lines that are no event (a late reply, a keepalive) are skipped: wait returns blocked, without a poll" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}")")"
serve junk
check "a blank line and one that is not JSON on the stream are skipped: wait returns blocked, without a poll" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}")")"
serve lag
check "agent.get lags a blocked event: wait reads it again and returns blocked, without a poll" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}" 3000)")"
serve slowget
check "agent.get after a blocked event answers only past the deadline: wait returns blocked, not a timeout" \
  "blocked|0" "$(quick "$(wait_cx "${SOCK}" 2000)")"
serve dribble
check "herdr answering the subscription a byte at a time still times out at the deadline" "rc=3" \
  "$(perl -e 'alarm 3; exec @ARGV' python3 -I "$(dirname "${SWARM}")/lib/herdr_events.py" "${SOCK}" w:7 500 >/dev/null 2>&1; echo "rc=$?")"
serve silent
check "a stream slice that times out moves on to the pane check and the next slice, without a poll" \
  "|0 2" "$(quick "$(SLICE=1000 wait_cx "${SOCK}" 2500)") $(grep -c '^agent read' "${ROOT}/herdr.log" || true)"
# python3 that fails on herdr_events.py (NOPY_RC, or 127 as when it is missing), and runs anything else.
mkdir -p "${ROOT}/nopy"
# shellcheck disable=SC2016 # the wrapper's own $1 and $@
printf '#!/bin/sh\ncase "$1" in *herdr_events.py) exit "${NOPY_RC:-127}" ;; esac\nexec %s "$@"\n' "$(command -v python3)" > "${ROOT}/nopy/python3"
chmod +x "${ROOT}/nopy/python3"
check "the stream fails with neither a state nor a timeout (127): wait polls herdr agent wait" \
  "idle|1" "$(quick "$(PRE="${ROOT}/nopy" wait_cx "${SOCK}")")"
check "the stream exits 1, as Python does on an uncaught error: wait polls herdr agent wait, not a timeout" \
  "idle|1" "$(quick "$(NOPY_RC=1 PRE="${ROOT}/nopy" wait_cx "${SOCK}")")"
serve drop
out="$(wait_cx "${SOCK}")"; ms="$(sed -n 's/^agent wait .*--timeout \([0-9]*\).*/\1/p' "${ROOT}/herdr.log")"
check "the stream ends mid-slice: wait polls herdr agent wait for what is left of the slice" \
  "idle|1 short" "$(quick "${out}") $([[ -n "${ms}" && ${ms} -lt 60000 ]] && echo short || echo "full (${ms})")"
serve refuse
check "a stream that refuses the subscription: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx "${SOCK}")")"
check "no socket: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx)")"
touch "${ROOT}/garbled"
out="$(quick "$(wait_cx)")"
check "herdr agent wait exits 0 with no agent status: the wait fails, it does not settle" \
  "|2 failed" "${out} $([[ "$(cat "${ROOT}/rc")" -ne 0 ]] && echo failed || echo "exit 0")"
rm -f "${ROOT}/garbled"; touch "${ROOT}/slowfail"
SLICE=1000 wait_cx "" 2500 >/dev/null; ms="$(sed -n 's/^agent wait .*--timeout \([0-9]*\).*/\1/p' "${ROOT}/herdr.log" | tail -1)"
check "a step that fails for real after 0.8 s: the last step waits only what is left, so the wait keeps to its timeout" \
  "short" "$([[ -n "${ms}" && ${ms} -le 1700 ]] && echo short || echo "long (${ms})")"
rm -f "${ROOT}/slowfail"
kill "${server}"; wait "${server}" 2>/dev/null || true; server=""   # its socket file stays behind
check "a socket nothing listens on any more: wait polls herdr agent wait, as before" "idle|1" "$(quick "$(wait_cx "${SOCK}")")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

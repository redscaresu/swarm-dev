#!/usr/bin/env bash
# agent_liveness_test.sh — `swarm.sh status` reads each agent's pane once (pane_check): a pane whose
# last turn ended on an `API Error:` line or an auto mode denial logs one api-error or auto-denied
# incident, once per occurrence, and the time its pane last changed lands in .swarm/panes, which
# dash shows beside the agent. herdr and gh are stubs on PATH: herdr lists this project's agents (and
# another project's) and prints ${ROOT}/pane-<pane> for `agent read`. Then flow counts both kinds per
# epic. Last, deliver_prompt reads an agent's own status when the prompt's reply can't be read, and
# sends the brief again only to an agent idle or done there.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
lacks() { ! grep -qE -- "$1" <<< "$2"; }

P="${ROOT}/proj"
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
touch "${P}/docs/stories/README.md"
git -C "${P}" init -q
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"
printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"'"${ERR_NAME:-s-err}"'","agent_status":"idle","pane_id":"w:1"},{"name":"s-deny","agent_status":"idle","pane_id":"w:2"},{"name":"s-ok","agent_status":"working","pane_id":"w:3"},{"name":"s-mid","agent_status":"working","pane_id":"w:4"},{"name":"s-prose","agent_status":"idle","pane_id":"w:5"},{"name":"s-again","agent_status":"idle","pane_id":"w:6"},{"name":"foreign","agent_status":"idle","pane_id":"w:9"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:1"},{"pane_id":"w:2"},{"pane_id":"w:3"},{"pane_id":"w:4"},{"pane_id":"w:5"},{"pane_id":"w:6"},{"pane_id":"w:9"}]}}' ;;
  "agent read") cat "$R/pane-$3" ;;
  "agent rename") ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/"*
printf 'w:1 s-err\nw:2 s-deny\nw:3 s-ok\nw:4 s-mid\nw:5 s-prose\nw:6 s-again\n' > "${P}/.swarm/state/t"

# s-err stopped on ECONNRESET; s-deny on an auto mode denial; s-ok had an API error, then carried on;
# s-mid's pane ends on an API error while herdr says it is still working (mid-turn); s-prose's own
# indented text mentions the classifier and an `API Error:` line. foreign is another project's agent, whose pane must not be read.
printf '%s\n' '⏺ Running the tests.' '⏺ API Error: Connection error (ECONNRESET)' '' '> ' > "${ROOT}/pane-w:1"
deny=('⏺ Reading the story.' '  ⎿  Read 40 lines' '⏺ Applying the plan.' '⏺ Bash(terraform apply)'
  '  ⎿  Error: Permission for this action was denied by the Claude Code auto mode classifier.' '     Reason: real cloud' '> ')
printf '%s\n' "${deny[@]}" > "${ROOT}/pane-w:2"
printf '%s\n' '⏺ API Error: 529 overloaded' '⏺ Carrying on.' > "${ROOT}/pane-w:3"
printf '%s\n' '⏺ Retrying.' '⏺ API Error: 529 overloaded' > "${ROOT}/pane-w:4"
printf '%s\n' '⏺ Noted for the brief:' '  commands can be denied by the Claude Code auto mode classifier.' '  API Error: lines mean retry.' '> ' > "${ROOT}/pane-w:5"
printf '%s\n' '⏺ API Error: foreign' > "${ROOT}/pane-w:9"

status() { (cd "${P}" && SWARM_PROJECT="${P}" HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status > /dev/null 2>&1) || true; }
incidents() { cut -f2,3,5 "${P}/.swarm/events.tsv" 2>/dev/null | grep '^incident' || true; }
status; status
check "two status runs log one event per stopped pane" test "$(incidents)" = "$(printf '%s\n' \
  $'incident\ts-err\tapi-error: API Error: Connection error (ECONNRESET)' \
  $'incident\ts-deny\tauto-denied: Error: Permission for this action was denied by the Claude Code auto mode classifier.')"
check "a pane ending on an API error mid-turn (herdr working) logs nothing" test "$(incidents | grep -c 's-mid')" = 0
check "an agent's own text naming the classifier or an API Error: line logs nothing" test "$(incidents | grep -c 's-prose')" = 0
check "status notes when each own pane last changed" test -s "${P}/.swarm/panes/s-ok" -a ! -e "${P}/.swarm/panes/foreign"
# The same ECONNRESET again, after s-err carried on (a read saw its reply), is a new occurrence: one
# more event.
printf '%s\n' '⏺ Retrying.' >> "${ROOT}/pane-w:1"
status
# A delivered tell to s-err (an ok tell:findings line), before this stop.
printf '%s\ttell:findings\ts-err\tw:me\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${P}/.swarm/events.tsv"
printf '%s\n' '⏺ API Error: Connection error (ECONNRESET)' >> "${ROOT}/pane-w:1"
status; status
check "a new stop on the same line logs one more event" test "$(incidents | grep -c 's-err')" = 2
# Retired (retire_agent renames it s-err-done and moves its pane record), the same stopped pane logs
# nothing more, the tell to s-err notwithstanding. Then a new agent in the same pane
# id logs its own stop there.
(cd "${P}" && PROJECT_DIR="${P}" STATE_DIR="${P}/.swarm/state" PATH="${ROOT}/bin:${PATH}" bash -c '
  die() { echo "$*" >&2; exit 1; }; agent_name() { printf "%s" "$1"; }
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  source "$1/../bin/lib/agents.sh"; retire_agent s-err > /dev/null' _ "${HERE}")
check "a retired agent's pane record goes with it" test -s "${P}/.swarm/panes/s-err-done" -a ! -e "${P}/.swarm/panes/s-err"
ERR_NAME=s-err-done status
check "a retired agent's stop is not logged again" test "$(incidents | grep -c 's-err')" = 2
ERR_NAME=s-new status
check "a new agent in a reused pane logs its own stop" test "$(incidents | grep -c 's-new')" = 1
# s-again stops, and wait resumes it (an ok resume line). A status before the pane redraws logs nothing
# more; once a read sees the resume taken up, a stop after it, with the same lines above it, is new.
again=('> Your last turn stopped on an API error; carry on where you stopped.' '⏺ API Error: 529 overloaded')
printf '%s\n' '⏺ Working.' "${again[@]}" "${again[@]}" > "${ROOT}/pane-w:6"
status
printf '%s\tresume\ts-again\tw:me\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${P}/.swarm/events.tsv"
status
check "a status between a resume and the pane redrawing logs nothing more" test "$(incidents | grep -c 's-again')" = 1
printf '%s\n' "${again[0]}" >> "${ROOT}/pane-w:6"
status
printf '%s\n' "${again[1]}" >> "${ROOT}/pane-w:6"
status
check "a stop after a resume, with the same lines above it, logs again" test "$(incidents | grep -c 's-again')" = 2
# s-deny's pane scrolls a line: the top line goes, a line comes under the stop. The stop is the same.
printf '%s\n' "${deny[@]:1}" '> carry on' > "${ROOT}/pane-w:2"
status
check "a line added under a stop, scrolling the pane, logs nothing more" test "$(incidents | grep -c 's-deny')" = 1
# pane_check alone, on a pane text file: pc <name> <file> reads it once (herdr says the turn ended).
L="${ROOT}/lib"; mkdir -p "${L}"
pc() { PROJECT_DIR="${L}" PANE_FILE="$2" bash -c 'source "$1/../bin/lib/agents.sh"; pane_text() { cat "${PANE_FILE}"; }
  turn_ended() { :; }; pane_check "$2" w:1 > /dev/null' _ "${HERE}" "$1"; }
stops() { grep -c $'^[^\t]*\tincident\t'"$1"$'\t' "${L}/.swarm/events.tsv" || true; }
ev() { printf '%s\t%s\t%s\tw:me\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "${L}/.swarm/events.tsv"; }
# wait resumes a stopped agent (an ok resume line) that never takes it up: wait's idle read of the
# same pane, with no resumed checksum, logs nothing more.
printf '%s\n' '⏺ Running.' '⏺ API Error: 500' > "${ROOT}/t-idle"
pc l-idle "${ROOT}/t-idle"; ev resume l-idle; pc l-idle "${ROOT}/t-idle"
check "wait's idle read after a resume not taken up logs nothing more" test "$(stops l-idle)" = 1
# A tell to a long slug is logged under the slug, not the agent's name. The agent replies, then stops
# again with the same lines above the stop: a new stop.
stop2=('  a' '  b' '⏺ Running.' '⏺ API Error: 529 overloaded')
printf '%s\n' "${stop2[@]}" > "${ROOT}/t-tell"
pc l-tell "${ROOT}/t-tell"; ev tell:findings l-tell-with-a-very-long-slug-past-the-name-cut
printf '%s\n' '> From the conductor: findings' '⏺ Fixing them.' >> "${ROOT}/t-tell"; pc l-tell "${ROOT}/t-tell"
printf '%s\n' "${stop2[@]}" >> "${ROOT}/t-tell"; pc l-tell "${ROOT}/t-tell"
check "after a tell to a long slug, a new stop with the same lines above it logs again" test "$(stops l-tell)" = 2
# A stop in the window's top lines, scrolled up by lines under it, is the same stop.
printf '%s\n' '⏺ Running.' '⏺ API Error: 500' '> ' > "${ROOT}/t-top"; pc l-top "${ROOT}/t-top"
printf '%s\n' '⏺ API Error: 500' '> ' '' > "${ROOT}/t-top"; pc l-top "${ROOT}/t-top"
check "a stop near the window's top that scrolls logs nothing more" test "$(stops l-top)" = 1
# A resume and a second API error both land before the next read: the second stop follows a new
# prompt, so it is logged too.
printf '%s\n' '⏺ API Error: first' > "${ROOT}/t-two"; pc l-two "${ROOT}/t-two"
printf '%s\n' '⏺ API Error: first' '> carry on' '⏺ API Error: second' > "${ROOT}/t-two"; pc l-two "${ROOT}/t-two"
check "a resume and a second API error before the next read log both stops" \
  test "$(grep $'\tl-two\t' "${L}/.swarm/events.tsv" | cut -f5)" = "$(printf '%s\n' 'api-error: API Error: first' 'api-error: API Error: second')"
# A stop whose prompt scrolls out of the window is the same stop.
printf '%s\n' '> go' '⏺ Running.' '⏺ API Error: 500' > "${ROOT}/t-off"; pc l-off "${ROOT}/t-off"
printf '%s\n' '⏺ Running.' '⏺ API Error: 500' '' > "${ROOT}/t-off"; pc l-off "${ROOT}/t-off"
check "a stop whose prompt scrolls out of the window logs nothing more" test "$(stops l-off)" = 1
# Two stops with no prompt in the window either time, a reply between them: two incidents.
printf '%s\n' '⏺ API Error: first' > "${ROOT}/t-np"; pc l-np "${ROOT}/t-np"
printf '%s\n' '⏺ API Error: first' '⏺ Retrying.' '⏺ API Error: second' > "${ROOT}/t-np"; pc l-np "${ROOT}/t-np"
check "two stops with no prompt in the window, a reply between them, log two incidents" test "$(stops l-np)" = 2
# A tool the agent ran printed an API error (its result, ⎿, ends the turn): no stop.
printf '%s\n' '⏺ Bash(curl -s localhost:8080/health)' '  ⎿  API Error: 500 upstream' '> ' > "${ROOT}/t-tool"; pc l-tool "${ROOT}/t-tool"
check "a turn ending on a tool result reading API Error: logs nothing" test "$(stops l-tool)" = 0
# A turn that ends on a tool result quoting the denial phrase (a grep over the docs) is no denial.
printf '%s\n' '⏺ Bash(grep -n classifier docs/reference.md)' \
  '  ⎿  706:saying "denied by the Claude Code auto mode classifier", it writes api-error or' '> ' > "${ROOT}/t-quote"
pc l-quote "${ROOT}/t-quote"
check "a tool result quoting the denial phrase logs nothing" test "$(stops l-quote)" = 0
# Eight reads of one stopped pane at once (status and a background wait, say) log it once.
R="${ROOT}/race"; mkdir -p "${R}"
n="$(PROJECT_DIR="${R}" bash -c 'source "$1/../bin/lib/agents.sh"
  pane_text() { printf "%s\n" "⏺ API Error: Connection reset"; }; turn_ended() { :; }
  for i in 1 2 3 4 5 6 7 8; do pane_check s-race w:1 > /dev/null & done; wait
  wc -l < "${EVENTS_LOG}"' _ "${HERE}")"
check "eight reads of one stop at once log one event" test "${n// /}" = 1

# dash shows the minutes since a pane last changed beside its agent, when status or wait read it within
# stall_minutes (the record's mtime), and its working count still agrees with status's
# (dash_defects_test's assertion).
FX="${ROOT}/fx"; mkdir -p "${FX}"
# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${FX}"
A="${FIXTURE_A}"
mkdir -p "${A}/.swarm/panes"; printf '1 2\t%s\n' "$((SWARM_DASH_NOW - 720))" > "${A}/.swarm/panes/a-building"
touch_ago 1 "${A}/.swarm/panes/a-building"
frame() { rm -f "${TMPDIR}"/swarm-dash-*; (cd "${A}" && DASH_W=100 "${FIXTURE_SWARM}" dash); }
out="$(frame)"
check "dash shows 12m beside an agent whose pane last changed 12 minutes ago" grep -qE '● a-building .*  pane 12m' <<< "${out}"
check "an agent with no pane record shows no pane age" lacks 'conduct-alpha-core .*pane' "${out}"
n="$(HERDR_ENV=1 SWARM_PROJECT="${A}" "${FIXTURE_SWARM}" status | grep -c '^  [^ ]*  *working  \[' || true)"
check "dash counts the ${n} agents status lists as working" grep -q " ${n} agents working" <<< "${out}"
touch_ago 30 "${A}/.swarm/panes/a-building"
check "a pane record no one read for stall_minutes shows no pane age" lacks 'a-building .*pane' "$(frame)"

# flow counts the stops per epic: s-err is e1's builder (its outcomes row), conduct-e1 its conductor,
# conduct-e2 a conductor that stopped before any builder of e2 started, s-err-done s-err retired.
F="${ROOT}/flowp"; mkdir -p "${F}/.swarm"; git -C "${F}" init -q
{
  printf '2026-10-02T12:00:00Z\tstory\ts-err\tw:1\tok\n'
  printf '2026-10-02T12:01:00Z\tincident\ts-err\tw:1\tapi-error: API Error: x\n'
  printf '2026-10-02T12:02:00Z\tincident\tconduct-e1\tw:1\tauto-denied: Error: y\n'
  printf '2026-10-02T12:03:00Z\tincident\tlost\tw:1\tapi-error: API Error: z\n'
  printf '2026-10-02T12:04:00Z\tconduct\te2\tw:0\tok\n'
  printf '2026-10-02T12:05:00Z\tincident\tconduct-e2\tw:1\tapi-error: API Error: w\n'
  printf '2026-10-02T12:06:00Z\tincident\ts-err-done\tw:1\tauto-denied: Error: v\n'
} > "${F}/.swarm/events.tsv"
printf '2026-10-02\tcode\ts-err\tclaude\topus\thigh\t-\n' > "${F}/.swarm/agents.tsv"
mkdir -p "${F}/docs/stories"; printf -- '---\nepic: e1\n---\n' > "${F}/docs/stories/s-err.md"
out="$(cd "${F}" || exit 1; env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" flow 2>&1 || true)"
check "flow counts api-error and auto-denied per epic" test "$(sed -n '/^epic	kind	stops$/,/^$/p' <<< "${out}" | sed '/^$/d')" = "$(printf '%s\n' \
  $'epic\tkind\tstops' $'-\tapi-error\t1' $'e1\tapi-error\t1' $'e1\tauto-denied\t2' $'e2\tapi-error\t1')"

# wait --stall on s-hung, a busy builder whose story started 2 hours ago with nothing since. Its last
# own work, a tool call, is 40 minutes old; its session wrote only compaction, summary and
# task-notice entries after it: no sign of life. ps (stubbed, from PS_TREE) shows its pane's shell
# (herdr's shell_pid 100) and the agent (200). Under the agent: an MCP server (250) and its worker,
# caffeinate (270), a hook-started MCP server under sh -c (280), and two Bash tool shells: 330, a
# run_in_background server started 90 minutes ago, and the newer 300, the foreground call, whose
# make test (given a token) runs scripts/test.sh, which runs the hung sleep (400). Another pane's
# tool shell runs an older sleep (590).
H="${ROOT}/hung"; HB="${ROOT}/hung-bin"; mkdir -p "${H}/.swarm/state" "${H}/docs/stories" "${HB}" "${ROOT}/projects/p"
touch "${H}/docs/stories/README.md"; git -C "${H}" init -q
printf -- '---\nstatus: ready\nkind: code\n---\n\n# s-hung\n' > "${H}/docs/stories/s-hung.md"
printf 'w:7 s-hung\n' > "${H}/.swarm/state/s-hung"
printf '2026-10-22\tcode\ts-hung\tclaude\topus\thigh\tsess-hung\n' > "${H}/.swarm/agents.tsv"
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S.000Z"))' "$1"; }
printf '%s\tstory\ts-hung\tw:me\tok\n' "$(ago 120 | cut -c1-19)Z" > "${H}/.swarm/events.tsv"
printf '[{"sessionId":"sess-hung","status":"busy"}]' > "${ROOT}/hung.json"
cp "${HERE}/claude_stub.sh" "${HB}/claude"
# herdr's wait times out with HUNG_WAIT=timeout (a codex agent's wait goes through herdr alone).
cat > "${HB}/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"s-hung","agent_status":"working","pane_id":"w:7"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:7"}]}}' ;;
  "pane process-info") [ "$4" = w:7 ] && echo '{"result":{"process_info":{"pane_id":"w:7","shell_pid":100}}}' ;;
  "agent read") echo '⏺ Running the tests.' ;;
  "agent wait") [ "${HUNG_WAIT:-}" = timeout ] && { echo '{"error":{"code":"timeout"}}' >&2; exit 1; }
    echo '{"result":{"agent":{"agent_status":"done"}}}' ;;
  *) exit 1 ;;
esac
STUB
# ps -o pid=,comm= prints ${PS_TREE}.comm when the test wrote one, else each command's first word.
cat > "${HB}/ps" <<'STUB'
#!/bin/sh
case "$*" in
  *comm=*) if [ -f "${PS_TREE}.comm" ]; then cat "${PS_TREE}.comm"; else awk '{ print $1, $4 }' "${PS_TREE}"; fi ;;
  *) cat "${PS_TREE}" ;;
esac
STUB
snap='/bin/zsh -c source /Users/u/.claude/shell-snapshots/snapshot-zsh-1.sh 2>/dev/null || true && eval'
tree=('  100     1  02:00:00 -zsh' '  200   100  02:00:00 claude --session-id sess-hung'
  '  250   200  01:59:30 node mcp-server.js' '  260   250  01:50:00 node worker.js' '  270   200     02:00 caffeinate -i -t 300'
  '  280   200  01:59:50 sh -c start-mcp.sh' '  281   280  01:59:49 node mcp2.js'
  "  300   200     45:03 ${snap} 'make test GH_TOKEN=SEKRIT'" '  310   300     45:02 make test GH_TOKEN=SEKRIT' '  320   310     45:01 bash scripts/test.sh'
  '  400   320     45:00 sleep 2700' "  330   200  01:30:00 ${snap} 'node server.js'" '  331   330  01:29:59 node server.js'
  "  590   999  1-03:00:01 ${snap} 'sleep 9999'" '  591   590  1-03:00:00 sleep 9999')
export PS_TREE="${ROOT}/ps.tree"; printf '%s\n' "${tree[@]}" > "${PS_TREE}"
chmod +x "${HB}/"*
log() { printf '%s\n' "$@" > "${ROOT}/projects/p/sess-hung.jsonl"; }
tool() { printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}' "$(ago "$1")"; }
idle=("{\"type\":\"system\",\"subtype\":\"compact_boundary\",\"timestamp\":\"$(ago 12)\"}"
  "{\"type\":\"user\",\"isCompactSummary\":true,\"timestamp\":\"$(ago 11)\",\"message\":{\"role\":\"user\",\"content\":\"This session is being continued.\"}}"
  "{\"type\":\"user\",\"timestamp\":\"$(ago 2)\",\"message\":{\"role\":\"user\",\"content\":\"<task-notification><task-id>b1</task-id></task-notification>\"}}"
  '{"type":"summary","summary":"Compacted while idle","leafUuid":"x"}')
hung_wait() { (cd "${H}" || exit 1; env -u HERDR_SOCKET_PATH HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_STALL_POLL_MS=1000 SWARM_WAIT_STARTED=$(( $(date +%s) - 7200 )) \
  CLAUDE_PROJECTS_DIR="${ROOT}/projects" CLAUDE_STUB_AGENTS="${ROOT}/hung.json" PATH="${HB}:${PATH}" bash "${SWARM}" wait --stall s-hung 3000 2>&1); }
# Its last own work, a tool call 40 minutes ago, came after every tool shell started: none is the
# foreground call, so the builder is hung outside Bash (an MCP call, a subagent, the API) and the old
# background server is not named.
log "$(tool 40)" "${idle[@]}"
if out="$(hung_wait)"; then rc=0; else rc=$?; fi
check "a builder whose newer log entries are only compaction and task notices is stalled?" grep -qE '^stalled: working 4[0-2] min' <<< "${out}"
check "wait --stall on it exits 3" test "${rc}" = 3
check "with no tool shell started since its last own work, nothing is named, and it says why" \
  grep -qE '; longest-running: none named \(no foreground Bash call: every tool shell running a command started before its last own work\)$' <<< "${out}"
# Its last own work 46 minutes ago, the tool call that started shell 300 a moment later: the sleep
# under make and test.sh is named, by program name and never by argument.
named='; longest-running: pid 400, 45 min: sleep \(under pid 310, 45 min: make > pid 320, 45 min: bash\)$'
log "$(tool 46)" "${idle[@]}"
if out="$(hung_wait)"; then rc=0; else rc=$?; fi
check "the stalled line names the leaf of the foreground tool shell's chain" grep -qE "${named}" <<< "${out}"
check "the incident line names it too" grep -qE $'\tincident\ts-hung\tw:me\tstalled: working 4[6-8] min .*'"${named}" "${H}/.swarm/events.tsv"
check "no argument (a token) reaches the stalled line or events.tsv" lacks 'SEKRIT|2700' "${out}$(cat "${H}/.swarm/events.tsv")"
# With no own work in the log at all, the newest tool shell is the foreground one, not the older
# background server.
log "${idle[@]}"
check "with no own work on record, the newest tool shell's leaf is named" grep -qE "${named}" <<< "$(hung_wait)"
# ps's comm, not the command's first word, names a program whose path holds a space.
log "$(tool 46)" "${idle[@]}"
{ awk '{ print $1, $4 }' "${PS_TREE}" | grep -v '^400 '; echo '400 /Applications/Visual Studio Code.app/Contents/MacOS/Electron'; } > "${PS_TREE}.comm"
check "a program whose path holds a space is named by ps's comm" grep -qE '; longest-running: pid 400, 45 min: Electron \(under' <<< "$(hung_wait)"
rm "${PS_TREE}.comm"
# With no tool shell (caffeinate and MCP servers only), nothing is named, and it says why.
printf '%s\n' "${tree[@]:0:7}" > "${PS_TREE}"
check "caffeinate and MCP servers with no tool shell name nothing" grep -qE '; longest-running: none named \(no Bash tool call is running a command\)$' <<< "$(hung_wait)"
# A codex builder (its agents.tsv line, no session): node runs the native codex binary, which runs
# the command. Its stalled line says no command is named.
printf '%s\n' "${tree[@]:0:1}" '  200   100  02:00:00 node /opt/homebrew/bin/codex' \
  '  210   200  02:00:00 /opt/homebrew/lib/node_modules/@openai/codex/vendor/codex/codex' '  400   210     45:00 sleep 2700' > "${PS_TREE}"
printf '2026-10-22\tcode\ts-hung\tcodex\tgpt\thigh\t-\n' >> "${H}/.swarm/agents.tsv"
check "a codex builder's stalled line says it names no command" grep -qE '; longest-running: none named \(a codex builder\)$' <<< "$(HUNG_WAIT=timeout hung_wait)"
printf '2026-10-22\tcode\ts-hung\tclaude\topus\thigh\tsess-hung\n' >> "${H}/.swarm/agents.tsv"
printf '%s\n' "${tree[@]}" > "${PS_TREE}"
# Its pane changed a minute ago (the record's checksum is not the pane's now), so it is not stuck either.
log "$(tool 40)" "${idle[@]}" "$(tool 5)"
printf 'other\t%s\n' "$(date +%s)" > "${H}/.swarm/panes/s-hung"
if out="$(hung_wait)"; then rc=0; else rc=$?; fi
check "the same log with a 5-minute-old tool call is no stall" test "${rc}:${out}" = "1:busy"
# A tool result 5 minutes old whose text holds a raw U+2028 (Node's JSON writer leaves it unescaped)
# is still one entry, and a sign of life.
log "$(tool 40)" "${idle[@]}" "{\"type\":\"user\",\"timestamp\":\"$(ago 5)\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"a$(printf '\342\200\250')b\"}]}}"
printf 'other\t%s\n' "$(date +%s)" > "${H}/.swarm/panes/s-hung"
if out="$(hung_wait)"; then rc=0; else rc=$?; fi
check "a tool result holding U+2028 is one entry, and a sign of life" test "${rc}:${out}" = "1:busy"
# A tool call whose timestamp has no offset is dated by the log's mtime (just now), never read as local
# time: in UTC+9 that would put it 9 hours back, a stall.
log "$(tool 40)" "${idle[@]}" "$(tool 1 | sed 's/\.000Z"/"/')"
printf 'other\t%s\n' "$(date +%s)" > "${H}/.swarm/panes/s-hung"
if out="$(TZ=Asia/Tokyo hung_wait)"; then rc=0; else rc=$?; fi
check "a timestamp with no offset is dated by the log's mtime, not as local time" test "${rc}:${out}" = "1:busy"
# The main log's own work 40 minutes old, a Task subagent's tool call 5 minutes ago: no stall.
log "$(tool 40)" "${idle[@]}"
mkdir -p "${ROOT}/projects/p/sess-hung/subagents"; tool 5 > "${ROOT}/projects/p/sess-hung/subagents/agent-a1.jsonl"
printf 'other\t%s\n' "$(date +%s)" > "${H}/.swarm/panes/s-hung"
if out="$(hung_wait)"; then rc=0; else rc=$?; fi
check "a Task subagent's 5-minute-old tool call is a sign of life" test "${rc}:${out}" = "1:busy"

# deliver_prompt with a stub herdr. The nth `agent prompt` answers the nth word of ${PROMPT_REPLY}
# (its last word from then on): a status, junk (an unreadable reply, exit 0), fail (plain text, exit
# 1: herdr down), or err:<code> (herdr's error on stderr, exit 1); warn:<word> prints a warning line on
# stderr first. The nth `agent get` answers the nth word of ${OWN} the same way, in herdr 0.9.5's shape
# (`herdr agent list` on live agents: done ones carry completion_seq equal to state_change_seq, working
# ones have no completion_seq key): done@<n> is done with both n; any other status has no
# completion_seq; - is no answer. SWARM_PROMPT_TIMEOUT_MS is ${PTO:-15000}, so prompt_settle reads 3
# times by default. With POSIX=1 deliver_prompt runs under set -o posix. dp prints "<rc>|<prompts
# sent>|<own reads>|<die message>", and leaves deliver_prompt's stderr in ${ROOT}/dp/err (dpwarn).
# The agent has no Claude session on record, so herdr alone answers.
dp() {
  local D="${ROOT}/dp"; rm -rf "${D}"; mkdir -p "${D}"; : > "${D}/prompts"; : > "${D}/gets"
  PROJECT_DIR="${D}" SWARM_SLEEP_SCALE=0.01 SWARM_PROMPT_TIMEOUT_MS="${PTO:-15000}" bash -c 'source "$1/../bin/lib/agents.sh"
    die() { echo "$*" > "${PROJECT_DIR}/died"; exit 1; }
    json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
    nth() { echo $2 | awk -v n="$1" "{ print (n <= NF ? \$n : \$NF) }"; }
    herdr() {
      local w n
      case "$1 $2" in
        "agent prompt") echo x >> "${PROJECT_DIR}/prompts"; w="$(nth "$(wc -l < "${PROJECT_DIR}/prompts")" "${PROMPT_REPLY}")"
          if [[ "${w}" == warn:* ]]; then echo "warning: server_binary_stale" >&2; w="${w#warn:}"; fi
          case "${w}" in
            junk) echo "not json" ;;
            fail) echo "connection refused" >&2; return 1 ;;
            err:*) echo "{\"error\":{\"code\":\"${w#err:}\"}}" >&2; return 1 ;;
            *) echo "{\"result\":{\"agent\":{\"agent_status\":\"${w}\"}}}" ;;
          esac ;;
        "agent get") echo x >> "${PROJECT_DIR}/gets"; n="$(wc -l < "${PROJECT_DIR}/gets" | tr -d " ")"; w="$(nth "${n}" "${OWN}")"
          case "${w}" in
            -) return 1 ;;
            done@*) echo "{\"result\":{\"agent\":{\"agent_status\":\"done\",\"state_change_seq\":${w#done@},\"completion_seq\":${w#done@}}}}" ;;
            *) echo "{\"result\":{\"agent\":{\"agent_status\":\"${w}\",\"state_change_seq\":${n}00}}}" ;;
          esac ;;
        *) return 1 ;;
      esac
    }
    [[ -z "${POSIX:-}" ]] || set -o posix
    echo brief > "${PROJECT_DIR}/brief"; deliver_prompt a "${PROJECT_DIR}/brief" w:1' _ "${HERE}" 2> "${D}/err" && rc=0 || rc=$?
  echo "${rc}|$(wc -l < "${D}/prompts" | tr -d ' ')|$(wc -l < "${D}/gets" | tr -d ' ')|$(cat "${D}/died" 2>/dev/null)"
}
# dpwarn — the warning the last dp left, that herdr sent the brief and did not show the turn start.
dpwarn() { grep "^warning: a: " "${ROOT}/dp/err" || true; }
see="see herdr agent read a"
unsure="a: it may or may not have the brief:"
notagain="it was not sent again, ${see}"
nobase="with nothing from before the prompt to compare it with; ${notagain}"
idle2="a: the brief was not taken up: herdr's reply to the brief could not be read twice, and herdr reads it idle with no turn finished since; ${see}"
unseen="warning: a: herdr sent it the brief once, and herdr did not show the turn start (it reads it"
check "a prompt reply of working sends one prompt and reads no own status after it" test "$(PROMPT_REPLY=working OWN=idle dp)" = "0|1|1|"
check "an unreadable prompt reply from an agent working on its own read is one prompt, and success" \
  test "$(PROMPT_REPLY=junk OWN='idle working' dp)" = "0|1|2|"
check "an unreadable prompt reply from an agent blocked on its own read is one prompt, and success" \
  test "$(PROMPT_REPLY=junk OWN='idle blocked' dp)" = "0|1|2|"
check "a brief herdr sent to an agent idle with no turn finished on every read is not sent again, and succeeds" \
  test "$(PROMPT_REPLY=junk OWN=idle dp)" = "0|1|4|"
check "and it warns that herdr sent it the brief and did not show the turn start" \
  test "$(dpwarn)" = "${unseen} idle with no turn finished since); it was not sent again, ${see}"
check "a brief to a slow starter, idle the whole settle after agent_prompt_stalled (sent), is not sent again: a warning" \
  test "$(PROMPT_REPLY='err:agent_prompt_stalled working' OWN=idle dp)|$(dpwarn | cut -c1-${#unseen})" = "0|1|4||${unseen}"
check "an idle agent whose reply could not be read is sent it again on evidence it was not taken, with no warning" \
  test "$(PROMPT_REPLY='fail working' OWN=idle dp)|$(dpwarn)" = "0|2|4||"
check "a slow starter still idle on the first reads after the prompt, then working, gets one prompt" \
  test "$(PROMPT_REPLY=err:agent_prompt_stalled OWN='idle idle idle working' dp)" = "0|1|4|"
check "an idle agent that took the prompt and is done by the first read (completion_seq now there) gets one prompt" \
  test "$(PROMPT_REPLY=junk OWN='idle done@7' dp)" = "0|1|2|"
check "an idle agent that reaches done between two reads gets one prompt" \
  test "$(PROMPT_REPLY=junk OWN='idle idle done@7' dp)" = "0|1|3|"
check "a done agent that finished another turn since (completion_seq moved) took the prompt: one prompt" \
  test "$(PROMPT_REPLY=junk OWN='done@3 done@9' dp)" = "0|1|2|"
check "an agent still done from an earlier turn (completion_seq unchanged) is not sent the brief again: a warning" \
  test "$(PROMPT_REPLY=junk OWN=done@3 dp)|$(dpwarn)" = "0|1|4||${unseen} done with no turn finished since); it was not sent again, ${see}"
check "a done agent whose first reply could not be read is sent it again, and works on it: success" \
  test "$(PROMPT_REPLY='fail junk' OWN='done@3 done@3 done@3 done@3 working' dp)" = "0|2|5|"
check "an agent working before the prompt and idle after it with no completion_seq is sent nothing more" \
  test "$(PROMPT_REPLY=junk OWN='working idle' dp)" = "1|1|4|${unsure} herdr sent it the brief once, then herdr reads it idle with no turn finished since; ${notagain}"
check "with no read before the prompt, a done agent is sent nothing more, and it may or may not have it" \
  test "$(PROMPT_REPLY=junk OWN='- done@3' dp)" = "1|1|4|${unsure} herdr sent it the brief once, then herdr reads it done, ${nobase}"
check "with no read before the prompt, an idle agent is sent nothing more" \
  test "$(PROMPT_REPLY=junk OWN='- idle' dp)" = "1|1|4|${unsure} herdr sent it the brief once, then herdr reads it idle, ${nobase}"
check "with herdr's status unknown before the prompt, an idle agent is sent nothing more" \
  test "$(PROMPT_REPLY=junk OWN='unknown idle' dp)" = "1|1|4|${unsure} herdr sent it the brief once, then herdr reads it idle, ${nobase}"
check "agent_prompt_stalled (sent; the agent slow to start) from an agent working on its own read is one prompt" \
  test "$(PROMPT_REPLY=err:agent_prompt_stalled OWN='idle working' dp)" = "0|1|2|"
check "agent_prompt_failed (raised after herdr took it) is never sent again blind: the own read decides" \
  test "$(PROMPT_REPLY=err:agent_prompt_failed OWN='idle working' dp)" = "0|1|2|"
check "two failed own reads in a row end the settle: no second prompt, and it says so" \
  test "$(PROMPT_REPLY=junk OWN='idle -' dp)" = "1|1|3|${unsure} herdr sent it the brief once, then herdr gave no status for it; ${notagain}"
check "one failed own read between two that answer does not end the settle" \
  test "$(PROMPT_REPLY=junk OWN='idle - working' dp)" = "0|1|3|"
check "an own status that stays unknown sends no second prompt and says so" \
  test "$(PROMPT_REPLY=junk OWN='idle unknown' dp)" = "1|1|4|${unsure} herdr sent it the brief once, then herdr reads it unknown with no turn finished since; ${notagain}"
check "no status after a second unreadable try says neither reply could be read" \
  test "$(PROMPT_REPLY=fail OWN='idle idle idle idle -' dp)" = "1|2|6|${unsure} herdr's reply to the brief could not be read twice, then herdr gave no status for it; ${notagain}"
check "herdr down (a failed prompt, no error it can read, no own status) says the reply could not be read" \
  test "$(PROMPT_REPLY=fail OWN=- dp)" = "1|1|3|${unsure} herdr's reply to the brief could not be read once, then herdr gave no status for it; ${notagain}"
check "herdr down on both tries never says the brief was sent" \
  test "$(PROMPT_REPLY=fail OWN=idle dp)" = "1|2|7|a: the brief was not taken up: herdr's reply to the brief could not be read twice, and herdr reads it idle with no turn finished since; ${see}"
check "one try sent and one unreadable says so" \
  test "$(PROMPT_REPLY='fail junk' OWN='idle idle idle idle -' dp)" = "1|2|6|${unsure} herdr sent it the brief once, and its reply to the other try could not be read, then herdr gave no status for it; ${notagain}"
check "agent_blocked (herdr sent nothing) on the first try fails at once, with no own read after it" \
  test "$(PROMPT_REPLY=err:agent_blocked OWN=working dp)" = "1|1|1|a: herdr did not send it the brief: it is blocked on a question (agent_blocked); answer it, ${see}"
check "agent_blocked behind a warning line on stderr is still agent_blocked" \
  test "$(PROMPT_REPLY=warn:err:agent_blocked OWN=blocked dp)" = "1|1|1|a: herdr did not send it the brief: it is blocked on a question (agent_blocked); answer it, ${see}"
check "a reply of working behind a warning line on stderr is one prompt" test "$(PROMPT_REPLY=warn:working OWN=idle dp)" = "0|1|1|"
check "agent_blocked on the second try, after a first prompt whose reply could not be read, may or may not have it" \
  test "$(PROMPT_REPLY='fail err:agent_blocked' OWN=idle dp)" = "1|2|4|${unsure} herdr's reply to the brief could not be read once, then herdr refused the next: it is blocked on a question (agent_blocked); ${notagain}"
check "agent_not_found (nothing sent) fails at once, naming it" \
  test "$(PROMPT_REPLY=err:agent_not_found OWN=working dp)" = "1|1|1|a: herdr did not send it the brief (agent_not_found); ${see}"
check "pane_not_found (a closed pane: nothing sent) fails at once, naming it" \
  test "$(PROMPT_REPLY=err:pane_not_found OWN=- dp)" = "1|1|1|a: herdr did not send it the brief (pane_not_found); ${see}"
check "server_unavailable (no herdr server: nothing sent) fails at once, naming it" \
  test "$(PROMPT_REPLY=err:server_unavailable OWN=- dp)" = "1|1|1|a: herdr did not send it the brief (server_unavailable); ${see}"
check "a prompt whose reply could not be read, then agent_not_found, says so" \
  test "$(PROMPT_REPLY='fail err:agent_not_found' OWN=idle dp)" = "1|2|4|a: herdr's reply to the brief could not be read once, then could not send it again (agent_not_found); ${see}"
check "prompt_settle reads for SWARM_PROMPT_TIMEOUT_MS: 10 s is 2 reads a try" \
  test "$(PTO=10000 PROMPT_REPLY=fail OWN=idle dp)" = "1|2|5|${idle2}"
check "under set -o posix the failure still counts the prompts in words" test "$(POSIX=1 PROMPT_REPLY=fail OWN=idle dp)" = "1|2|7|${idle2}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

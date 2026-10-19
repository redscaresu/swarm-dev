#!/usr/bin/env bash
# agent_liveness_test.sh — `swarm.sh status` reads each agent's pane once (pane_check): a pane whose
# last turn ended on an `API Error:` line or an auto mode denial logs one api-error or auto-denied
# incident, once per occurrence, and the time its pane last changed lands in .swarm/panes, which
# dash shows beside the agent. herdr and gh are stubs on PATH: herdr lists this project's agents (and
# another project's) and prints ${ROOT}/pane-<pane> for `agent read`. Then flow counts both kinds per
# epic.
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
  "agent list") echo '{"result":{"agents":[{"name":"'"${ERR_NAME:-s-err}"'","agent_status":"idle","pane_id":"w:1"},{"name":"s-deny","agent_status":"idle","pane_id":"w:2"},{"name":"s-ok","agent_status":"working","pane_id":"w:3"},{"name":"s-mid","agent_status":"working","pane_id":"w:4"},{"name":"s-prose","agent_status":"idle","pane_id":"w:5"},{"name":"foreign","agent_status":"idle","pane_id":"w:9"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:1"},{"pane_id":"w:2"},{"pane_id":"w:3"},{"pane_id":"w:4"},{"pane_id":"w:5"},{"pane_id":"w:9"}]}}' ;;
  "agent read") cat "$R/pane-$3" ;;
  "agent rename") ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/"*
printf 'w:1 s-err\nw:2 s-deny\nw:3 s-ok\nw:4 s-mid\nw:5 s-prose\n' > "${P}/.swarm/state/t"

# s-err stopped on ECONNRESET; s-deny on an auto mode denial; s-ok had an API error, then carried on;
# s-mid's pane ends on an API error while herdr says it is still working (mid-turn); s-prose's own
# indented text mentions the classifier. foreign is another project's agent, whose pane must not be read.
printf '%s\n' '⏺ Running the tests.' '  ⎿  API Error: Connection error (ECONNRESET)' '' '> ' > "${ROOT}/pane-w:1"
deny=('⏺ Reading the story.' '  ⎿  Read 40 lines' '⏺ Applying the plan.' '⏺ Bash(terraform apply)'
  '  ⎿  Error: Permission for this action has been denied by the Claude Code auto mode classifier.' '     Reason: real cloud' '> ')
printf '%s\n' "${deny[@]}" > "${ROOT}/pane-w:2"
printf '%s\n' '  ⎿  API Error: 529 overloaded' '⏺ Carrying on.' > "${ROOT}/pane-w:3"
printf '%s\n' '⏺ Retrying.' '  ⎿  API Error: 529 overloaded' > "${ROOT}/pane-w:4"
printf '%s\n' '⏺ Noted for the brief:' '  commands can be denied by the Claude Code auto mode classifier.' '> ' > "${ROOT}/pane-w:5"
printf '%s\n' '  ⎿  API Error: foreign' > "${ROOT}/pane-w:9"

status() { (cd "${P}" && SWARM_PROJECT="${P}" HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status > /dev/null 2>&1) || true; }
incidents() { cut -f2,3,5 "${P}/.swarm/events.tsv" 2>/dev/null | grep '^incident' || true; }
status; status
check "two status runs log one event per stopped pane" test "$(incidents)" = "$(printf '%s\n' \
  $'incident\ts-err\tapi-error: API Error: Connection error (ECONNRESET)' \
  $'incident\ts-deny\tauto-denied: Error: Permission for this action has been denied by the Claude Code auto mode classifier.')"
check "a pane ending on an API error mid-turn (herdr working) logs nothing" test "$(incidents | grep -c 's-mid')" = 0
check "an agent's own text naming the classifier logs nothing" test "$(incidents | grep -c 's-prose')" = 0
check "status notes when each own pane last changed" test -s "${P}/.swarm/panes/s-ok" -a ! -e "${P}/.swarm/panes/foreign"
# The same ECONNRESET again, after s-err carried on, is a new occurrence: one more event.
printf '%s\n' '⏺ Retrying.' '  ⎿  API Error: Connection error (ECONNRESET)' >> "${ROOT}/pane-w:1"
status; status
check "a new stop on the same line logs one more event" test "$(incidents | grep -c 's-err')" = 2
# Retired (retire_agent renames it s-err-done), the same stopped pane logs nothing more.
ERR_NAME=s-err-done status
check "a retired agent's stop is not logged again" test "$(incidents | grep -c 's-err')" = 2
# s-deny's pane scrolls a line: the top line goes, a line comes under the stop. The stop is the same.
printf '%s\n' "${deny[@]:1}" '> carry on' > "${ROOT}/pane-w:2"
status
check "a line added under a stop, scrolling the pane, logs nothing more" test "$(incidents | grep -c 's-deny')" = 1
# retire_agent moves its pane record to the retired name, so a new s-err starts with none.
(cd "${P}" && PROJECT_DIR="${P}" STATE_DIR="${P}/.swarm/state" PATH="${ROOT}/bin:${PATH}" bash -c '
  die() { echo "$*" >&2; exit 1; }; agent_name() { printf "%s" "$1"; }
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  source "$1/../bin/lib/agents.sh"; retire_agent s-err > /dev/null' _ "${HERE}")
check "a retired agent's pane record goes with it" test -s "${P}/.swarm/panes/s-err-done" -a ! -e "${P}/.swarm/panes/s-err"
# Eight reads of one stopped pane at once (status and a background wait, say) log it once.
R="${ROOT}/race"; mkdir -p "${R}"
n="$(PROJECT_DIR="${R}" bash -c 'source "$1/../bin/lib/agents.sh"
  pane_text() { printf "%s\n" "⎿ API Error: Connection reset"; }; turn_ended() { :; }
  for i in 1 2 3 4 5 6 7 8; do pane_check s-race w:1 > /dev/null & done; wait
  wc -l < "${EVENTS_LOG}"' _ "${HERE}")"
check "eight reads of one stop at once log one event" test "${n// /}" = 1

# dash shows the minutes since a pane last changed beside its agent, and its working count still
# agrees with status's (dash_defects_test's assertion).
FX="${ROOT}/fx"; mkdir -p "${FX}"
# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${FX}"
A="${FIXTURE_A}"
mkdir -p "${A}/.swarm/panes"; printf '1 2\t%s\t\n' "$((SWARM_DASH_NOW - 720))" > "${A}/.swarm/panes/a-building"
frame() { rm -f "${TMPDIR}"/swarm-dash-*; (cd "${A}" && DASH_W=100 "${FIXTURE_SWARM}" dash); }
out="$(frame)"
check "dash shows 12m beside an agent whose pane last changed 12 minutes ago" grep -qE '● a-building .*  pane 12m' <<< "${out}"
check "an agent with no pane record shows no pane age" lacks 'conduct-alpha-core .*pane' "${out}"
n="$(HERDR_ENV=1 SWARM_PROJECT="${A}" "${FIXTURE_SWARM}" status | grep -c '^  [^ ]*  *working  \[' || true)"
check "dash counts the ${n} agents status lists as working" grep -q " ${n} agents working" <<< "${out}"

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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

#!/usr/bin/env bash
# bg_running_test.sh — agents.sh's bg_running bounds every background task by its launch age, whoever
# calls it. A review agent's background shell hung on a read for 17.5 hours, and nothing reported a
# stall, because wait's quiet-pane check (pane_quiet) and wait --lead's stuck: lines (stuck_lines)
# called bg_running with no stall_minutes, so any task counted as life at any age (#891). Over one
# fixture transcript per case, with stall_minutes 30 in the config (TEST_RUN_STALLS 3, so 90 minutes):
#   - a non-test background task launched past the bound is no life, with no stall_minutes passed
#     (as those two callers call it) and with one; launched inside the bound it is
#   - a background test run (make test) past the same age keeps TEST_RUN_STALLS' result: no life; inside
#     it, life. A test suite still running in the pane is test_running's, at any age, and not read here
#   - the bound follows the config: stall_minutes 10 puts a 60-minute-old task past it
#   - a task whose end was logged is no life, whatever its age
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <expected> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$2") <(echo "$3") || true; fails=$((fails + 1)); fi
}

mkdir -p "${ROOT}/projects/p" "${ROOT}/proj/.swarm"
printf '2026-11-14\treview-agent\tr\tclaude\topus\thigh\tsess-r\n' > "${ROOT}/proj/.swarm/agents.tsv"
TR="${ROOT}/projects/p/sess-r.jsonl"
NOW="$(date +%s)"

# ago <minutes> — that long before NOW as a transcript timestamp (UTC, Z).
ago() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(sys.argv[1]))))' $((NOW - $1 * 60)); }
# launch <minutes ago> <command> — a Bash tool call run in the background and its launch result, task b1.
launch() {
  python3 -c 'import json, sys
cmd, at = sys.argv[1], sys.argv[2]
print(json.dumps({"type": "assistant", "timestamp": at, "message": {"content": [
  {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": cmd, "run_in_background": True}}]}}))
print(json.dumps({"type": "user", "timestamp": at, "message": {"content": [
  {"type": "tool_result", "tool_use_id": "t1", "content": "Command running in background with ID: b1"}]},
  "toolUseResult": {"stdout": "", "backgroundTaskId": "b1"}}))' "$2" "$(ago "$1")" > "${TR}"
}
# ended — b1's end, a task-notification with a status.
ended() { printf '{"type":"user","message":{"content":"<task-notification>\\n<task-id>b1</task-id>\\n<status>completed</status>\\n</task-notification>"}}\n' >> "${TR}"; }
# alive <stall_minutes in the config> [<stall_minutes passed>] — yes when bg_running reads agent r's
# session as waiting on a live background task, else no. agents.sh sourced alone, as swarm.sh sources it.
alive() (
  SWARM_HOME="${REPO}"; PROJECT_DIR="${ROOT}/proj"; CLAUDE_PROJECTS_DIR="${ROOT}/projects"; CFG_stall_minutes="$1"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"   # its AGENTS_LOG and CLAUDE_PROJECTS come from the two above
  if bg_running r ${2:+"$2"} "" "${NOW}"; then echo yes; else echo no; fi
)

HUNG='x=1; $=x 2>/dev/null'   # #891's line: zsh runs NULLCMD (cat) on it, which waits for good
launch 95 "${HUNG}"
check "a non-test background task launched past 3 x stall_minutes is no life, with no stall_minutes passed" no "$(alive 30)"
check "the same task with stall_minutes passed is no life" no "$(alive 30 30)"
launch 85 "${HUNG}"
check "a non-test background task launched inside 3 x stall_minutes is life, with no stall_minutes passed" yes "$(alive 30)"
check "the same task with stall_minutes passed is life" yes "$(alive 30 30)"

launch 95 'make test JOBS=4'
check "a background test run launched past 3 x stall_minutes is no life, as TEST_RUN_STALLS sets it" no "$(alive 30 30)"
check "the same test run with no stall_minutes passed is no life either" no "$(alive 30)"
launch 85 'make test JOBS=4'
check "a background test run launched inside 3 x stall_minutes is life" yes "$(alive 30 30)"

launch 60 "${HUNG}"
check "the bound follows the config: with stall_minutes 10, a task launched 60 minutes ago is no life" no "$(alive 10)"
check "and with stall_minutes 30 the same task is life" yes "$(alive 30)"

launch 5 "${HUNG}"; ended
check "a task whose end was logged is no life" no "$(alive 30)"

[[ ${fails} -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all bg_running checks passed"

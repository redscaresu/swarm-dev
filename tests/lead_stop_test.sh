#!/usr/bin/env bash
# lead_stop_test.sh — hooks/lead-stop.sh against a stub swarm.sh. The hook is copied beside a
# bin/swarm.sh stub that prints $STUB_NEXT for next and $STUB_STATUS for status (next sleeps first
# or exits 1 after on request) and records each command it ran; each case checks the hook's stdout
# and the events.tsv line it left.
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/lead-stop.sh"
root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${root}"' EXIT
export CLAUDE_CONFIG_DIR="${root}/claude-config"   # under its own root, so parallel runs share no ~/.claude
mkdir -p "${root}/plugin/hooks" "${root}/plugin/bin" "${root}/project/.claude/swarm" "${root}/project/docs/stories" "${root}/project/docs/epics"
cp "${HOOK}" "${root}/plugin/hooks/lead-stop.sh"
cat > "${root}/plugin/bin/swarm.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "${STUB_RAN}"
[[ "$1" != next || -z "${STUB_SLEEP:-}" ]] || sleep "${STUB_SLEEP}"
case "$1" in
  next) printf '%s\nwhy\n' "${STUB_NEXT}" ;;
  config) echo "${STUB_BOARD}" ;;
  status) rows="${STUB_STATUS:-Agents: none open}"
          [[ "${2:-}" == --all ]] || rows="$(grep -v '  idle: ' <<< "${rows}")"   # as status hides idle agents
          printf '%s\n\nWaiting on you\n  nothing\n\nNext\n  %s\n' "${rows}" "${STUB_NEXT}" ;;
esac
[[ "$1" != next || -z "${STUB_FAIL:-}" ]] || exit 1   # after its line, so only the exit status says it failed
EOF
chmod +x "${root}/plugin/bin/swarm.sh"
export STUB_RAN="${root}/ran" STUB_BOARD="${root}/project/docs" SWARM_SLEEP_SCALE=0.2   # a 2-second timeout
unset SWARM_AGENT SWARM_PROJECT
events="${root}/project/.swarm/events.tsv"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# run [<stop_hook_active>] — the hook on a Stop input in the project; stdout in out, the events.tsv
# line it added (or nothing) in ev, the stub's commands in ran.
run() {
  rm -f "${events}" "${STUB_RAN}"
  out="$(printf '{"hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "${root}/project" "${1:-false}" \
    | "${root}/plugin/hooks/lead-stop.sh")"
  ev="$(cut -f2,3,5 "${events}" 2>/dev/null | tr '\t' ' ')" || ev=""
  ran="$(cat "${STUB_RAN}" 2>/dev/null | tr '\n' ' ')" || ran=""
}

# blocked <line> — out is the block decision naming <line>.
blocked() {
  [[ "$(python3 -c 'import json, sys; d = json.loads(sys.argv[1]); print(d["decision"], d["reason"])' "${out}")" \
    == "block next says: $1. Start it now, or tell the user why it cannot start." ]]
}

STUB_NEXT="plan-epic X" run
check "plan-epic with no agent blocks, naming the line" blocked "plan-epic X"
check "the block is logged" [ "${ev}" = "lead-stop plan-epic blocked" ]

STUB_NEXT="plan-epic X" STUB_STATUS=$'Agents: 1 need a look or are working, 0 idle or done\n  survey  working  [scope-X 1-2]' run
check "plan-epic with survey in scope-X allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop plan-epic allowed" ]

for st in "EMPTY: no agent started in this pane; close it" "gone: session ended" "unknown: no session state"; do
  STUB_NEXT="plan-epic X" STUB_STATUS="Agents: 1 need a look or are working, 0 idle or done"$'\n'"  survey  ${st}  [scope-X 1-2]" run
  check "plan-epic with survey ${st%%:*} in scope-X blocks" blocked "plan-epic X"
  check "that block is logged" [ "${ev}" = "lead-stop plan-epic blocked" ]
done

for st in "Agents: not inside herdr, so their states are not available" $'Agents\n  (herdr gave no agent list)'; do
  STUB_NEXT="plan-epic X" STUB_STATUS="${st}" run
  check "plan-epic with no agent list (${st##* }) allows" [ -z "${out}" ]
  check "that allow is logged" [ "${ev}" = "lead-stop plan-epic allowed" ]
done

STUB_NEXT="conduct E" STUB_STATUS=$'Agents: 1 need a look or are working, 0 idle or done\n  conduct-e  working  [conduct-e 1-2]' run
check "conduct with its conductor working allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop conduct allowed" ]

STUB_NEXT="story s1" STUB_STATUS=$'Agents: 1 need a look or are working, 0 idle or done\n  other  working  [other 1-2]' run
check "story with only another agent blocks" blocked "story s1"
check "that block is logged" [ "${ev}" = "lead-stop story blocked" ]

# agents <row>... — STUB_STATUS's Agents section with these rows.
agents() { printf 'Agents: %s need a look or are working, 0 idle or done' "$#"; printf '\n  %s' "$@"; }
idle="idle: finished, or waiting for its next step"

long="a-story-slug-well-past-thirty-two-characters"
STUB_NEXT="resume ${long}" STUB_STATUS="$(agents "${long:0:32}  working  [${long:0:32} 1-2]")" run
check "resume with a slug past 32 characters finds its builder" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop resume allowed" ]
STUB_NEXT="conduct ${long}" STUB_STATUS="$(agents "conduct-${long:0:24}  working  [c 1-2]")" run
check "conduct with an epic past 24 characters finds its conductor" [ -z "${out}" ]
STUB_NEXT="story Big_Slug" STUB_STATUS="$(agents "big_slug  working  [big_slug 1-2]")" run
check "story finds its builder by agent_name's lowercase name" [ -z "${out}" ]

STUB_NEXT="plan-epic X" STUB_STATUS="$(agents "critic  working  [scope-X-2 1-5]")" run
check "plan-epic with an agent in scope-X-2 allows" [ -z "${out}" ]
STUB_NEXT="plan-epic X" STUB_STATUS="$(agents "critic  working  [scope-X2 1-5]" "other  working  [scope-X-y 1-6]")" run
check "plan-epic with agents in scope-X2 and scope-X-y only blocks" blocked "plan-epic X"

STUB_NEXT="plan-epic X" STUB_STATUS="$(agents "survey  ${idle}  [scope-X 1-2]")" run
check "plan-epic with survey idle in scope-X allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop plan-epic allowed" ]
mkdir -p "${root}/project/.swarm/X"; echo '{}' > "${root}/project/.swarm/X/survey.json"
echo "# X" > "${root}/project/docs/epics/X.md"; touch -t 202001010000 "${root}/project/docs/epics/X.md"
STUB_NEXT="plan-epic X" run
check "plan-epic with its planners closed and their answers in .swarm/X allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop plan-epic allowed" ]
touch -t 201901010000 "${root}/project/.swarm/X/survey.json"
STUB_NEXT="plan-epic X" run
check "plan-epic with only an answer older than the epic (a previous plan) blocks" blocked "plan-epic X"
echo '{"cut' > "${root}/project/.swarm/X/survey.json"
STUB_NEXT="plan-epic X" run
check "plan-epic with only an answer that is not JSON blocks" blocked "plan-epic X"
rm -rf "${root}/project/.swarm/X" "${root}/project/docs/epics/X.md"
git -C "${root}/project" init -q && git -C "${root}/project" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "${root}/project" branch board/scope-X
STUB_NEXT="plan-epic X" run
check "plan-epic with no agent and the board/scope-X branch (planned alone) allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop plan-epic allowed" ]
STUB_NEXT="plan-epic Y" run
check "plan-epic Y with only board/scope-X blocks" blocked "plan-epic Y"
rm -rf "${root}/project/.git"

STUB_NEXT="collect conduct-e" STUB_STATUS="$(agents "conduct-e  ${idle}  [conduct-e 1-2]")" run
check "collect with its conductor idle (its report written) blocks" blocked "collect conduct-e"
check "that block is logged" [ "${ev}" = "lead-stop collect blocked" ]
STUB_NEXT="collect conduct-e" STUB_STATUS="$(agents "conduct-e  working  [conduct-e 1-2]")" run
check "collect with its conductor still working allows" [ -z "${out}" ]

STUB_NEXT="story s1" STUB_STATUS="$(agents "conduct-backlog-proj-abc123  working  [conduct-backlog-proj-abc123 1-2]")" run
check "story with the backlog conductor working allows" [ -z "${out}" ]
STUB_NEXT="story s1" STUB_STATUS="$(agents "conduct-backlog-proj-abc123-done2  done (retired)  [conduct-backlog-proj-abc123 1-2]")" run
check "story with only a retired backlog conductor blocks" blocked "story s1"

report="${root}/project/.swarm/conduct-backlog.report.md"
echo "not started: s1 (waits on s2's merge)" > "${report}"
touch -t 202001010000 "${root}/project/docs/stories" "${root}/project/docs/epics"
touch -t 202101010000 "${report}"   # after the board, and well before anything written below
STUB_NEXT="story s1" run
check "story with the backlog report newer than every board item allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop story allowed" ]
echo x > "${root}/project/docs/stories/s3.md"
STUB_NEXT="story s1" run
check "story with a board item newer than the report blocks" blocked "story s1"
STUB_NEXT="resume s1" run
check "resume of a slug the report lists as not started allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop resume allowed" ]
STUB_NEXT="resume s" run
check "resume of a slug the report names only as a prefix blocks" blocked "resume s"
rm -f "${report}" "${root}/project/docs/stories/s3.md"

for step in "wait conduct-E" gate "done"; do
  STUB_NEXT="${step}" run
  check "${step} allows" [ -z "${out}" ]
  check "${step} allow is logged" [ "${ev}" = "lead-stop ${step%% *} allowed" ]
  check "${step} never reads status" [ "${ran}" = "next " ]
done

STUB_NEXT="plan-epic X" run true
check "stop_hook_active allows" [ -z "${out}" ]
check "stop_hook_active runs nothing and logs nothing" [ -z "${ran}${ev}" ]

STUB_NEXT="plan-epic X" SWARM_AGENT=builder run
check "SWARM_AGENT allows" [ -z "${out}" ]
check "SWARM_AGENT runs no next and logs nothing" [ -z "${ran}${ev}" ]

start=$(date +%s)
STUB_NEXT="plan-epic X" STUB_SLEEP=30 run
check "a next past the timeout allows with empty stdout" [ -z "${out}" ]
check "the timeout ends it within 10 seconds" [ $(($(date +%s) - start)) -lt 10 ]
check "the timeout is logged as allowed" [ "${ev}" = "lead-stop - allowed" ]

start=$(date +%s)
STUB_NEXT="plan-epic X" STUB_SLEEP=30 SWARM_SLEEP_SCALE=0 run
check "with SWARM_SLEEP_SCALE=0 the timeout is a second, not none" [ $(($(date +%s) - start)) -lt 10 ]
check "that timeout allows with empty stdout" [ -z "${out}" ]

STUB_NEXT="plan-epic X" STUB_FAIL=1 run
check "a next that exits 1 allows with empty stdout" [ -z "${out}" ]
check "that failure is logged as allowed" [ "${ev}" = "lead-stop - allowed" ]

mv "${root}/project/.claude" "${root}/project/.claude-off"
STUB_NEXT="plan-epic X" run
check "outside a swarm project it allows and runs nothing" [ -z "${out}${ran}${ev}" ]
STUB_NEXT="plan-epic X" SWARM_PROJECT="${root}/elsewhere" run
check "a SWARM_PROJECT that is not one changes nothing" [ -z "${out}${ran}${ev}" ]
mkdir -p "${root}/other/.claude/swarm"
STUB_NEXT="plan-epic X" SWARM_PROJECT="${root}/other" run
check "a SWARM_PROJECT that is one runs the hook there" blocked "plan-epic X"
check "it logs to that project" [ "$(cut -f2,3,5 "${root}/other/.swarm/events.tsv" | tr '\t' ' ')" = "lead-stop plan-epic blocked" ]
mv "${root}/project/.claude-off" "${root}/project/.claude"

[ "${fails}" -eq 0 ] || { echo "${fails} failed"; exit 1; }

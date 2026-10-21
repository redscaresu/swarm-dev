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
mkdir -p "${root}/plugin/hooks" "${root}/plugin/bin" "${root}/project/.claude/swarm"
cp "${HOOK}" "${root}/plugin/hooks/lead-stop.sh"
cat > "${root}/plugin/bin/swarm.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "${STUB_RAN}"
[[ "$1" != next || -z "${STUB_SLEEP:-}" ]] || sleep "${STUB_SLEEP}"
case "$1" in
  next) printf '%s\nwhy\n' "${STUB_NEXT}" ;;
  status) printf '%s\n\nWaiting on you\n  nothing\n\nNext\n  %s\n' "${STUB_STATUS:-Agents: none open}" "${STUB_NEXT}" ;;
esac
[[ "$1" != next || -z "${STUB_FAIL:-}" ]] || exit 1   # after its line, so only the exit status says it failed
EOF
chmod +x "${root}/plugin/bin/swarm.sh"
export STUB_RAN="${root}/ran" SWARM_SLEEP_SCALE=0.2   # a 2-second timeout
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

STUB_NEXT="conduct E" STUB_STATUS=$'Agents: 1 need a look or are working, 0 idle or done\n  conduct-E  working  [conduct-E 1-2]' run
check "conduct with its conductor working allows" [ -z "${out}" ]
check "that allow is logged" [ "${ev}" = "lead-stop conduct allowed" ]

STUB_NEXT="story s1" STUB_STATUS=$'Agents: 1 need a look or are working, 0 idle or done\n  other  working  [other 1-2]' run
check "story with only another agent blocks" blocked "story s1"
check "that block is logged" [ "${ev}" = "lead-stop story blocked" ]

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

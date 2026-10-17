#!/usr/bin/env bash
# merge_guard_test.sh — hooks/merge-guard.sh, the plugin's PreToolUse hook on Bash: inside a swarm
# project it exits 2 on every raw merge (gh pr merge, gh api, graphql, through a shell, eval, an
# interpreter, a pipe or a file) and on swarm.sh merge joined to another command, and lets a lone
# swarm.sh merge and plain mentions through; outside one it allows everything. A block writes one
# incident line to the project's .swarm/events.tsv, and hooks.json runs the script on Bash calls.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO}/hooks/merge-guard.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
P="${ROOT}/proj"; OUT="${ROOT}/elsewhere"; LOG="${P}/.swarm/events.tsv"
mkdir -p "${P}/.claude/swarm" "${OUT}"
echo "merge = agent" > "${P}/.claude/swarm/config"
git -C "${P}" init -q
git -C "${P}" add .claude && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm init
git -C "${P}" worktree add -q "${ROOT}/wt" -b story/x
fails=0
U="https://github.com/o/r/pull/7"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# call <cwd> <command> [hook command] — the hook's exit code on a Bash call of <command> from <cwd>.
call() {
  local json rc=0 run="${3:-}"
  [[ -n "${run}" ]] || run="bash '${HOOK}'"
  json="$(python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
    "cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "$1" "$2")"
  (cd "$1" && printf '%s' "${json}" | CLAUDE_PLUGIN_ROOT="${REPO}" bash -c "${run}" >/dev/null 2>&1) || rc=$?
  echo "${rc}"
}
lines() { if [[ -f "${LOG}" ]]; then wc -l < "${LOG}" | tr -d ' '; else echo 0; fi; }
exits() { [[ "$(call "$1" "$3")" == "$2" ]]; } # <cwd> <code> <command>

blocks() { # <name> <command>: 2 in the project, 0 outside it
  check "blocks ${1}" exits "${P}" 2 "$2"
  check "outside a project allows ${1}" exits "${OUT}" 0 "$2"
}
passes() { # <name> <command>
  check "allows ${1}" exits "${P}" 0 "$2"
  check "outside a project allows ${1}" exits "${OUT}" 0 "$2"
}

blocks "gh pr merge" "gh pr merge 7 --squash"
blocks "gh api .../pulls/<n>/merge" "gh api -X PUT repos/o/r/pulls/7/merge"
blocks "graphql mergePullRequest" "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'"
blocks "bash -c" 'bash -c "gh pr merge 1"'
blocks "eval" 'eval "gh pr merge 1"'
blocks "python3 -c" "python3 -c \"import os; os.system('gh pr merge 1')\""
blocks "a heredoc written to m.sh and run" "$(printf '%s\n' "cat > m.sh <<'EOF'" 'gh pr merge 1' EOF 'bash m.sh')"
blocks "a pipe into a shell" "echo 'gh pr merge 1' | sh"
# shellcheck disable=SC2016 # the substitution is the hook's to see
blocks "a substitution" 'echo "$(gh pr merge 1)"'
blocks "swarm.sh merge after &&" "cd x && swarm.sh merge ${U}"
blocks "swarm.sh merge before ;" "swarm.sh merge ${U}; echo"
blocks "swarm.sh merge before &" "swarm.sh merge ${U} & echo"
passes "a lone swarm.sh merge" "SWARM_PROJECT=/p /x/bin/swarm.sh merge --head abc ${U} > /tmp/m.log 2>&1"
passes "echo of gh pr merge" 'echo "gh pr merge"'
passes "grep for swarm.sh merge" "grep 'swarm.sh merge' f"
passes "a PR body that mentions gh pr merge" "$(printf '%s\n' "gh pr create --title t --body \"\$(cat <<'EOF'" "it's gh pr merge (no)" EOF ')"')"
passes "gh pr view mergeable" "gh pr view 7 --json mergeable"

was="$(lines)"
call "${P}" "gh pr merge 7" >/dev/null
check "a block writes one incident line" test "$(lines)" -eq $((was + 1))
# shellcheck disable=SC2016 # awk's fields
check "the line has record_event's five fields" awk -F'\t' 'END { exit !(NF == 5 && $1 ~ /^20..-..-..T..:..:..Z$/ && $2 == "incident" && $5 == "merge-blocked: gh pr merge") }' "${LOG}"
call "${P}" "swarm.sh merge ${U}" >/dev/null
check "a pass writes nothing" test "$(lines)" -eq $((was + 1))
check "a worktree's block logs to its main checkout" exits "${ROOT}/wt" 2 "gh pr merge 7"
check "  ... in the main checkout's events.tsv" test "$(lines)" -eq $((was + 2))

hook_cmd="$(python3 -c 'import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
print("\n".join(e["hooks"][0]["command"] for e in h if e["matcher"] == "Bash"))' "${REPO}/hooks/hooks.json")"
# shellcheck disable=SC2016 # the literal hooks.json holds
check "hooks.json runs the guard under CLAUDE_PLUGIN_ROOT on Bash" test "${hook_cmd}" == '"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh"'
check "hooks.json's command blocks a raw gh pr merge" test "$(call "${P}" "gh pr merge 7" "${hook_cmd}")" == 2

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

#!/usr/bin/env bash
# merge_guard_test.sh — hooks/merge-guard.sh, the plugin's PreToolUse hook on Bash: inside a swarm
# project it exits 2 on the raw merges it knows (gh pr merge, gh api, graphql, through a shell, eval,
# an interpreter, a pipe or a file, spelled through quotes or not) and on swarm.sh merge joined to
# another command, and lets a lone swarm.sh merge and plain mentions through; outside one it allows
# everything. A call that says merge is refused when the check cannot run. It also blocks a cd before
# ;, git checkout over uncommitted changes and, for a swarm agent, git moving the main checkout and a
# kill by pattern or of every process. A block writes one incident line to the project's
# .swarm/events.tsv, and hooks.json runs the script on Bash calls.
set -euo pipefail
unset SWARM_AGENT  # the lead's session unless a case sets it

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO}/hooks/merge-guard.sh"
# Under /tmp, not ${TMPDIR}: the fast path skips a call that never says merge, so no path in a call
# may say it, or every case would reach the parser whatever its command.
tmp="$(mktemp -d /tmp/guard.XXXXXX)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
case "${ROOT}" in *[Mm][Ee][Rr][Gg][Ee]*) echo "the test dir ${ROOT} says merge" >&2; rm -rf "${ROOT}"; exit 1 ;; esac
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${ROOT}/proj"; OUT="${ROOT}/elsewhere"; LOG="${P}/.swarm/events.tsv"
mkdir -p "${P}/.claude/swarm" "${OUT}"
echo "merge = agent" > "${P}/.claude/swarm/config"
echo f > "${P}/f"; echo g > "${P}/g"; echo s > "${P}/s"
git -C "${P}" init -q
git -C "${P}" add .claude f g s && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm init
W="${ROOT}/wt"
git -C "${P}" worktree add -q "${W}" -b story/x
echo changed >> "${W}/f"  # f has unstaged changes in the worktree, s staged ones; g has none
echo changed >> "${W}/s" && git -C "${W}" add s
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
blocks "a ( ) group piped into a shell" "(echo 'gh pr merge 1') | sh"
blocks "a { } group piped into a shell" "{ echo 'gh pr merge 1'; } | sh"
# shellcheck disable=SC2016 # the heredoc's substitution is the hook's to see
blocks "a substitution in an unquoted heredoc" "$(printf '%s\n' 'cat <<EOF' '$(gh pr merge 7)' EOF)"
# shellcheck disable=SC2016 # the heredoc's substitution is the hook's to see
passes "a substitution in a quoted heredoc" "$(printf '%s\n' "cat <<'EOF'" '$(gh pr merge 7)' EOF)"
# shellcheck disable=SC2016 # the substitution is the hook's to see
blocks "a heredoc into sh -c" "$(printf '%s\n' 'sh -c "$(cat)" <<EOF' 'gh pr merge 1' EOF)"
blocks "a here-string into python3 -c" "python3 -c \"import os, sys; os.system(sys.stdin.read())\" <<< 'gh pr merge 1'"
blocks "a pipe into gh api graphql --input -" "echo '{\"query\":\"mutation{mergePullRequest(input:{}){clientMutationId}}\"}' | gh api graphql --input -"
blocks "gh -Ro/r pr merge" "gh -Ro/r pr merge 7"
blocks "gh -R=o/r pr merge" "gh -R=o/r pr merge 7"
blocks "gh pr -Ro/r merge" "gh pr -Ro/r merge 7"
passes "a python3 script's argument" "python3 tools/notes.py 'gh pr merge'"
blocks 'gh pr "mer"ge' 'gh pr "mer"ge 7'
blocks "gh pr me''rge" "gh pr me''rge 7"
blocks 'gh pr mer\ge' 'gh pr mer\ge 7'
blocks "a quoted spelling piped into a shell" "echo 'gh pr mer\"\"ge 1' | sh"

was="$(lines)"
call "${P}" "gh pr merge 7" >/dev/null
check "a block writes one incident line" test "$(lines)" -eq $((was + 1))
# shellcheck disable=SC2016 # awk's fields
check "the line has record_event's five fields" awk -F'\t' 'END { exit !(NF == 5 && $1 ~ /^20..-..-..T..:..:..Z$/ && $2 == "incident" && $5 == "merge-blocked: gh pr merge") }' "${LOG}"
call "${P}" "swarm.sh merge ${U}" >/dev/null
check "a pass writes nothing" test "$(lines)" -eq $((was + 1))
check "a worktree's block logs to its main checkout" test "$(call "${W}" "gh pr merge 7")/$(lines)" == "2/$((was + 2))"

# swarm.sh init makes a .claude/swarm/ and no config. Left untracked, a story worktree beside the
# repo has no .claude at all, so the guard looks from its main checkout too.
Q="${ROOT}/plain"; mkdir -p "${Q}/.claude/swarm"
git -C "${Q}" init -q && git -C "${Q}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "${Q}" worktree add -q "${ROOT}/plain-wt/s" -b story/s
check "a .claude/swarm/ with no config is a project" exits "${Q}" 2 "gh pr merge 7"
check "its story worktree, with no .claude, is guarded" exits "${ROOT}/plain-wt/s" 2 "gh pr merge 7"
check "  ... and logs to the main checkout" test "$(wc -l < "${Q}/.swarm/events.tsv" | tr -d ' ')" -eq 2

# Once a call says merge the guard fails closed: no python3, input it cannot read, a call too big
# for an environment variable.
feed() { local rc=0; PATH="${2:-${PATH}}" "${BASH}" "${HOOK}" < "$1" >/dev/null 2>&1 || rc=$?; echo "${rc}"; } # <file> [PATH]
mkdir -p "${ROOT}/nopy" && for b in cat sed tr; do ln -s "$(command -v "${b}")" "${ROOT}/nopy/${b}"; done
printf '{"cwd": "%s", "tool_input": {"command": "git merge x"}}' "${OUT}" > "${ROOT}/says-merge.json"
printf '{"tool_input": {"command": "ls"}}' > "${ROOT}/ls.json"
printf '{"cwd": "%s", "tool_input": {"command": "git checkout -- f"}}' "${W}" > "${ROOT}/says-git.json"
printf '{"tool_input": {"command": "merge' > "${ROOT}/bad.json"
python3 -c 'import json, sys
for c in ("gh pr merge 7 # ", "echo \"gh pr merge 7\" # "):
    print(json.dumps({"cwd": sys.argv[1], "tool_input": {"command": c + "x" * 3000000}}))' "${P}" > "${ROOT}/big.jsonl"
head -1 "${ROOT}/big.jsonl" > "${ROOT}/big-merge.json"; tail -1 "${ROOT}/big.jsonl" > "${ROOT}/big-echo.json"
check "with no python3 a call that says merge is refused" test "$(feed "${ROOT}/says-merge.json" "${ROOT}/nopy")" == 2
check "  ... and one that does not passes" test "$(feed "${ROOT}/ls.json" "${ROOT}/nopy")" == 0
check "  ... and so does one that only says git, which fails open" test "$(feed "${ROOT}/says-git.json" "${ROOT}/nopy")" == 0
check "input it cannot read that says merge is refused" test "$(feed "${ROOT}/bad.json")" == 2
check "a 3 MB raw merge is refused" test "$(feed "${ROOT}/big-merge.json")" == 2
check "a 3 MB mention reaches the check and passes" test "$(feed "${ROOT}/big-echo.json")" == 0

# The rules read the command alone, never the cwd or description. A python3 that exits 1 refuses
# any call that reaches it and says merge.
mkdir -p "${ROOT}/badpy" && printf '#!/bin/sh\nexit 1\n' > "${ROOT}/badpy/python3" && chmod +x "${ROOT}/badpy/python3"
printf '{"cwd": "%s/github.com/merge-cd", "tool_input": {"command": "ls github.com/abcd", "description": "merge, then cd and git"}}' "${ROOT}" > "${ROOT}/says-none.json"
printf '{"cwd": "%s", "tool_input": {"command": "git status", "description": "before the merge"}}' "${W}" > "${ROOT}/desc-merge.json"
check "a call that says merge, git and cd only in its cwd and description skips the check" test "$(feed "${ROOT}/says-none.json" "${ROOT}/badpy:${PATH}")" == 0
check "a git call whose description says merge fails open" test "$(feed "${ROOT}/desc-merge.json" "${ROOT}/badpy:${PATH}")" == 0
# An error in the lose-work rules lets the call through, even one that says merge: status output
# that is not UTF-8 makes the dirty-file check raise.
mkdir -p "${ROOT}/oddgit" && printf '#!/bin/sh\ncase " $* " in *" status "*) printf "\\377\\n"; exit 0 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "${ROOT}/oddgit/git" && chmod +x "${ROOT}/oddgit/git"
check "an error in the lose-work rules fails open, even in a call that says merge" test "$(PATH="${ROOT}/oddgit:${PATH}" call "${W}" "git checkout -- f # before the merge")" == 0

hook_cmd="$(python3 -c 'import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
print("\n".join(e["hooks"][0]["command"] for e in h if e["matcher"] == "Bash"))' "${REPO}/hooks/hooks.json")"
# shellcheck disable=SC2016 # the literal hooks.json holds
check "hooks.json runs the guard under CLAUDE_PLUGIN_ROOT on Bash" test "${hook_cmd}" == '"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh"'
check "hooks.json's command blocks a raw gh pr merge" test "$(call "${P}" "gh pr merge 7" "${hook_cmd}")" == 2

# as <agent|lead> <cwd> <code> <command> — hooks.json's command exits <code>, in a swarm agent's
# session (SWARM_AGENT set) or the lead's.
as() {
  local rc
  if [[ "$1" == agent ]]; then rc="$(SWARM_AGENT=b1 call "$2" "$4" "${hook_cmd}")"; else rc="$(call "$2" "$4" "${hook_cmd}")"; fi
  [[ "${rc}" == "$3" ]]
}
check "an agent's git checkout main in the main checkout blocks" as agent "${P}" 2 "git checkout main"
for c in "switch main" "restore x" "reset --hard" "stash" "clean -fd"; do
  check "an agent's git ${c} in the main checkout blocks" as agent "${P}" 2 "git ${c}"
done
check "an agent's git -C <main checkout> restore x blocks" as agent "${W}" 2 "git -C ${P} restore x"
check "an agent's cd <main checkout> && git stash blocks" as agent "${W}" 2 "cd ${P} && git stash"
check "git checkout -- f on a dirty f blocks" as lead "${W}" 2 "git checkout -- f"
check "git checkout f on a dirty f blocks" as lead "${W}" 2 "git checkout f"
check "cd /nope; cp a b blocks" as lead "${W}" 2 "cd /nope; cp a b"
# A cd that is a loop's condition runs no body when it fails, so the cd rule skips it.
check "until cd /nope; do sleep 1; done passes" as lead "${W}" 0 "until cd /nope; do sleep 1; done"
check "while ! cd /nope; do sleep 1; done passes" as lead "${W}" 0 "while ! cd /nope; do sleep 1; done"
check "  ... but a cd before ; in its body still blocks" as lead "${W}" 2 "while true; do cd /nope; cp a b; done"
check "  ... and logs guard-blocked to the main checkout" test "$(tail -1 "${LOG}" | cut -f5)" == "guard-blocked: cd before ;"
check "an agent's git checkout main in a story worktree passes" as agent "${W}" 0 "git checkout main"
check "an agent's git -C <story worktree> restore x passes" as agent "${P}" 0 "git -C ${W} restore x"
for c in "stash list" "stash show" "clean -n" "clean --dry-run" "clean -nd"; do
  check "an agent's git ${c} in the main checkout passes" as agent "${P}" 0 "git ${c}"
done
check "the lead's git checkout main in the main checkout passes" as lead "${P}" 0 "git checkout main"
check "git checkout -- g on a clean g passes" as lead "${W}" 0 "git checkout -- g"
check "git checkout -- s on a staged-only s passes" as lead "${W}" 0 "git checkout -- s"
check "git checkout HEAD -- s on a staged-only s blocks" as lead "${W}" 2 "git checkout HEAD -- s"
check "git checkout -q HEAD s on a staged-only s blocks" as lead "${W}" 2 "git checkout -q HEAD s"
# The hook's git status only reads: it leaves a stale index as it is, so it never takes index.lock.
idx="$(git -C "${W}" rev-parse --path-format=absolute --git-path index)"
touch -t 202001010000 "${W}/g"; was_idx="$(cksum < "${idx}")"
check "the hook's git status leaves a stale index alone" test "$(call "${W}" "git checkout -- g")/$(cksum < "${idx}")" == "0/${was_idx}"
# shellcheck disable=SC2016 # the substitution is the hook's to see
check 'DIR=$(cd "$(dirname x)"; pwd) passes' as lead "${W}" 0 'DIR=$(cd "$(dirname x)"; pwd)'
check "cd d || exit 1 && cp a b passes" as lead "${W}" 0 "cd d || exit 1 && cp a b"
# A conflict in g: checking out a side resolves it and drops no work.
C="${ROOT}/conflict"; G=(git -c user.name=t -c user.email=t@t -C "${C}")
git -C "${P}" worktree add -q "${C}" -b story/c
echo d > "${C}/g"; "${G[@]}" commit -qam d; "${G[@]}" branch -q story/d; "${G[@]}" reset -q --hard HEAD~1
echo c > "${C}/g"; "${G[@]}" commit -qam c; "${G[@]}" merge -q story/d >/dev/null 2>&1 || true
check "git checkout --theirs g on a conflicted g passes" as lead "${C}" 0 "git checkout --theirs g"
check "outside a project, cd /nope; cp a b passes" as lead "${OUT}" 0 "cd /nope; cp a b"
# A kill by name or pattern, or of PID 0 or -1 (every process the user owns), can hit another
# session's process; a kill of a PID the agent holds cannot.
# shellcheck disable=SC2016 # the substitution is the hook's to see
for c in "pkill -f sleep" "killall sleep" 'kill $(pgrep sleep)' "kill -9 -1" "kill -- -1" "kill 0"; do
  was="$(lines)"
  check "an agent's ${c} blocks" as agent "${W}" 2 "${c}"
  check "  ... and logs guard-blocked: pattern-kill" test "$(lines)/$(tail -1 "${LOG}" | cut -f5)" == "$((was + 1))/guard-blocked: pattern-kill"
  check "the lead's ${c} passes" as lead "${W}" 0 "${c}"
done
# shellcheck disable=SC2016 # $! is the hook's to see
for c in 'kill $!' "kill 1234" "kill -9 1234" "kill -s TERM 1234" "echo pkill"; do
  check "an agent's ${c} passes" as agent "${W}" 0 "${c}"
  check "the lead's ${c} passes" as lead "${W}" 0 "${c}"
done
# An agent waits on CI with swarm.sh wait-pr, never a watch or a loop of its own; one read passes.
for c in "gh pr checks 271 --watch" "until gh pr checks 271; do sleep 30; done" "while ! gh -R o/r pr checks 271; do sleep 30; done"; do
  was="$(lines)"
  check "an agent's ${c} blocks" as agent "${W}" 2 "${c}"
  check "  ... and logs guard-blocked: gh pr checks loop" test "$(lines)/$(tail -1 "${LOG}" | cut -f5)" == "$((was + 1))/guard-blocked: gh pr checks loop"
  check "the lead's ${c} passes" as lead "${W}" 0 "${c}"
done
check "an agent's gh pr checks 271 passes" as agent "${W}" 0 "gh pr checks 271"
check "the lead's gh pr checks 271 passes" as lead "${W}" 0 "gh pr checks 271"
check "an agent's until gh pr checks inside a for loop blocks" as agent "${W}" 2 "for i in 1 2; do until gh pr checks 271; do sleep 30; done; done"
check "an agent's gh pr checks after a for loop inside a while loop blocks" as agent "${W}" 2 "while true; do for i in 1; do :; done; gh pr checks 271; done"
check "an agent's gh pr checks inside a while loop's body blocks" as agent "${W}" 2 "while true; do gh pr checks 271; sleep 30; done"
# shellcheck disable=SC2016 # $l is the loop's own
check "an agent's single gh pr checks piped into a while loop passes" as agent "${W}" 0 'gh pr checks 271 | while read -r l; do echo "$l"; done'
check "an agent's gh pr checks after a finished while loop passes" as agent "${W}" 0 "while false; do :; done; gh pr checks 271"
# The fast path sends pr checks to the parser, and a bare checks word past it.
mkdir -p "${ROOT}/markpy" && printf '#!/bin/sh\n: > "%s/py-ran"\nexit 0\n' "${ROOT}" > "${ROOT}/markpy/python3" && chmod +x "${ROOT}/markpy/python3"
ran() { rm -f "${ROOT}/py-ran"; call "${W}" "$1" "PATH='${ROOT}/markpy':\${PATH} bash '${HOOK}'" >/dev/null; if [[ -e "${ROOT}/py-ran" ]]; then echo parser; else echo fast; fi; }
check "make checks takes the fast path" test "$(ran "make checks")" == fast
check "gh pr checks 271 reaches the parser" test "$(ran "gh pr checks 271")" == parser

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

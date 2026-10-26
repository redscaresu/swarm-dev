#!/usr/bin/env bash
# user_caught_reminder_test.sh — hooks/user-caught-reminder.sh on UserPromptSubmit inputs: it prints
# the reminder in the lead's session in a swarm project, and nothing for an agent (SWARM_AGENT or
# SWARM_GH_CALLER), from a story worktree or outside a swarm project; it exits 0 every time. Also:
# hooks.json runs it on UserPromptSubmit beside agent-state.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO}/hooks/user-caught-reminder.sh"
root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${root}"' EXIT
root="$(cd "${root}" && pwd -P)"
export CLAUDE_CONFIG_DIR="${root}/claude-config"   # under its own root, so parallel runs share no ~/.claude
unset SWARM_AGENT SWARM_GH_CALLER SWARM_PROJECT   # a builder running make test has them
REMINDER='If this message points out a problem the swarm or the lead missed, log it first: swarm.sh intervene user-caught "<what they found>".'
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

g() { git -C "${project}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# A swarm project's main checkout, with a story worktree beside it, and a git repo with no config.
project="${root}/project" other="${root}/other"
mkdir -p "${project}/.claude/swarm" "${project}/docs" "${other}"
: > "${project}/.claude/swarm/config"
g init -q && g add -A && g commit -q -m init
g worktree add -q "${root}/project-wt/story-a" -b story/story-a
git -C "${other}" init -q

# run <cwd> [<from>] [<input>] — the hook on a UserPromptSubmit input naming <cwd> (or on <input>),
# run from <from> (<cwd> by default); its stdout in out, its exit code in rc.
run() {
  local input
  input="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"you missed a red CI run"}' "$1")"
  rc=0
  out="$(cd "${2:-$1}" && printf '%s' "${3:-${input}}" | "${HOOK}")" || rc=$?
}

run "${project}"
check "the lead's session in a swarm project gets the reminder" [ "${out}|${rc}" = "${REMINDER}|0" ]
run "${project}/docs"
check "and from a folder inside the project" [ "${out}|${rc}" = "${REMINDER}|0" ]
run "${project}" "${project}" 'not json'
check "an input it cannot read falls back to the hook's cwd" [ "${out}|${rc}" = "${REMINDER}|0" ]
run "${project}" "${other}"
check "the input's cwd counts, not the hook's: the project's from elsewhere gets the reminder" [ "${out}|${rc}" = "${REMINDER}|0" ]
run "${other}" "${project}"
check "and a folder outside a swarm project, run from the project, gets nothing" [ "${out}|${rc}" = "|0" ]
run "${root}/project-wt/story-a" "${project}"
check "and a story worktree, run from the project, gets nothing" [ "${out}|${rc}" = "|0" ]

SWARM_GH_CALLER=story-a run "${project}"
check "an agent's session (SWARM_GH_CALLER) gets nothing" [ "${out}|${rc}" = "|0" ]
SWARM_AGENT=story-a run "${project}"
check "a Claude agent's session (SWARM_AGENT) gets nothing" [ "${out}|${rc}" = "|0" ]
run "${root}/project-wt/story-a"
check "a session in a story worktree gets nothing" [ "${out}|${rc}" = "|0" ]
SWARM_PROJECT="${project}" run "${root}/project-wt/story-a"
check "nor with SWARM_PROJECT naming the project" [ "${out}|${rc}" = "|0" ]
run "${other}"
check "outside a swarm project it prints nothing" [ "${out}|${rc}" = "|0" ]

# hooks.json's UserPromptSubmit commands, run as Claude Code would (through sh, under
# CLAUDE_PLUGIN_ROOT), on an input naming the project, from outside it: agent-state.sh prints
# nothing, so the reminder is all.
cmds="$(python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"]:
    for h in entry["hooks"]:
        print(h["command"], h.get("timeout"))' "${REPO}/hooks/hooks.json")"
# shellcheck disable=SC2016 # the literal hooks.json holds
check "hooks.json runs it on UserPromptSubmit after agent-state.sh, each with a 5 s timeout" [ "${cmds}" = \
  '"${CLAUDE_PLUGIN_ROOT}/hooks/agent-state.sh" working 5
"${CLAUDE_PLUGIN_ROOT}/hooks/user-caught-reminder.sh" 5' ]
printed=""
while IFS= read -r cmd; do
  printed+="$(cd "${other}" && printf '{"cwd":"%s"}' "${project}" | CLAUDE_PLUGIN_ROOT="${REPO}" sh -c "${cmd% *}")"
done <<< "${cmds}"
check "and the lead's prompt gets the reminder through them" [ "${printed}" = "${REMINDER}" ]

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"

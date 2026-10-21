#!/bin/sh
# agent-state.sh <working|idle|blocked|release|session> — the plugin's Claude Code hooks on
# UserPromptSubmit (working), Stop (idle), Notification (blocked), SessionEnd (release) and
# SessionStart (session), hooks/hooks.json. start_agent reports each agent's resume command to herdr
# with `pane report-agent --source swarm`, which can make swarm the authority for the pane's state in
# place of herdr's screen reading, so the agent's own session reports its state the same way.
# release hands the pane back only when the user quits (SessionEnd's reason prompt_input_exit or
# logout): a herdr restart ends the session too, and a release then would drop the command that
# restores the agent. session, on a cleared or resumed session, reports the resume command
# (SWARM_RESUME, resume_file's argv) again with the new session id, so a restart resumes that one.
# Only a swarm agent's session (SWARM_AGENT, set through --settings) in a herdr pane reports. herdr
# runs in the background, so a herdr that hangs never holds a prompt, and the hook always exits 0 and
# prints nothing, since a UserPromptSubmit hook's output reaches the agent's context.
# ponytail: a herdr that never answers leaves its call running; give it a timeout if one ever piles up.
input="$(cat)"
[ -n "${SWARM_AGENT:-}" ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
h="${HERDR_BIN_PATH:-herdr}"
case "$1" in
  release) printf '%s' "${input}" | grep -Eq '"reason"[[:space:]]*:[[:space:]]*"(prompt_input_exit|logout)"' \
             && "${h}" pane release-agent --source swarm --agent claude "${HERDR_PANE_ID}" ;;
  session) id="$(printf '%s' "${input}" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
           [ -n "${id}" ] && [ -f "${SWARM_RESUME:-}" ] || exit 0
           set --; prev=""
           while IFS= read -r a; do
             [ "${prev}" != --resume ] || a="${id}"
             set -- "$@" "${a}"; prev="${a}"
           done < "${SWARM_RESUME}"
           "${h}" pane report-agent-session --source swarm --agent claude --agent-session-id "${id}" "${HERDR_PANE_ID}" -- "$@" ;;
  working|idle|blocked) "${h}" pane report-agent --source swarm --agent claude --state "$1" "${HERDR_PANE_ID}" ;;
esac < /dev/null > /dev/null 2>&1 &
exit 0

#!/bin/sh
# agent-state.sh <working|idle|blocked|release> — the plugin's Claude Code hooks on UserPromptSubmit
# (working), Stop (idle), Notification (blocked) and SessionEnd (release), hooks/hooks.json. start_agent
# reports each agent's resume command to herdr with `pane report-agent --source swarm`, which can make
# swarm the authority for the pane's state in place of herdr's screen reading, so the agent's own
# session reports its state the same way. release hands the pane back only when the user quits
# (SessionEnd's reason prompt_input_exit or logout): a herdr restart ends the session too, and a
# release then would drop the command that restores the agent. Only a swarm agent's session
# (SWARM_AGENT, set through --settings) in a herdr pane reports. It always exits 0 and prints nothing,
# since a UserPromptSubmit hook's output reaches the agent's context.
input="$(cat)"
[ -n "${SWARM_AGENT:-}" ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
h="${HERDR_BIN_PATH:-herdr}"
case "$1" in
  release) printf '%s' "${input}" | grep -Eq '"reason"[[:space:]]*:[[:space:]]*"(prompt_input_exit|logout)"' \
             && "${h}" pane release-agent --source swarm --agent claude "${HERDR_PANE_ID}" ;;
  working|idle|blocked) "${h}" pane report-agent --source swarm --agent claude --state "$1" "${HERDR_PANE_ID}" ;;
esac > /dev/null 2>&1
exit 0

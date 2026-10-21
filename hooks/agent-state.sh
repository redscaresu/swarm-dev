#!/bin/sh
# agent-state.sh <working|idle|blocked|release> — the plugin's Claude Code hooks, hooks/hooks.json:
# working on UserPromptSubmit and PostToolUse (a tool ran, so an answered permission prompt no longer
# blocks), idle on Stop, StopFailure (a turn that ended on an API error) and a cleared or resumed
# SessionStart, blocked on a permission Notification, release on SessionEnd. start_agent reports each
# agent's resume command to herdr with `pane report-agent --source swarm`, and each report here
# carries it again (SWARM_RESUME, resume_file's argv), so whichever report herdr keeps, a restart
# resumes the session the agent is in.
# Only the pane's own session reports: the one after --resume in that argv. A `claude -p` an agent
# runs from Bash inherits SWARM_AGENT, HERDR_PANE_ID and SWARM_RESUME, so without that check it would
# report its own state and session into the agent's pane. A SessionStart that clears the session
# (source clear) moves the argv to the new id first; a nested session starts with source startup.
# The hook input is read as JSON, so the top-level session_id counts, never one in a tool's input or
# output. Every report has a --seq of the time in nanoseconds, taken before the call is forked, so
# herdr keeps the newest event's report whatever order the calls arrive in. release hands the pane
# back only when the user quits (SessionEnd's reason prompt_input_exit or logout): a herdr restart
# ends the session too, and a release then would drop the command that restores the agent. herdr
# runs in the background, so a herdr that hangs never holds a prompt, and the hook always exits 0 and
# prints nothing, since a UserPromptSubmit hook's output reaches the agent's context.
# ponytail: a herdr that never answers leaves its call running; give it a timeout if one ever piles up.
input="$(cat)"
[ -n "${SWARM_AGENT:-}" ] && [ -n "${HERDR_PANE_ID:-}" ] && [ -f "${SWARM_RESUME:-}" ] || exit 0
h="${HERDR_BIN_PATH:-herdr}" state="$1"
out="$(printf '%s' "${input}" | python3 -c '
import json, sys, time
print(time.time_ns())
try:
    d = json.load(sys.stdin)
except ValueError:
    d = None
d = d if isinstance(d, dict) else {}
for k in ("session_id", "hook_event_name", "source", "reason"):
    v = d.get(k)
    print(v if isinstance(v, str) and "\n" not in v else "")' 2>/dev/null)" || exit 0
{ read -r seq; read -r id; read -r event; read -r source; read -r reason; } <<EOF
${out}
EOF
[ -n "${id}" ] || exit 0
if [ "${event}" = SessionStart ] && [ "${source}" = clear ]; then
  tmp="${SWARM_RESUME}.$$"
  if ! { (umask 077; awk -v id="${id}" 'p == "--resume" { $0 = id } { p = $0; print }' "${SWARM_RESUME}" > "${tmp}") \
      && mv -f "${tmp}" "${SWARM_RESUME}"; }; then
    rm -f "${tmp}"; exit 0
  fi
fi
[ "${id}" = "$(sed -n '/^--resume$/{n;p;q;}' "${SWARM_RESUME}")" ] || exit 0
case "${state}" in
  release) [ "${reason}" = prompt_input_exit ] || [ "${reason}" = logout ] || exit 0
           set -- release-agent --source swarm --agent claude --seq "${seq}" "${HERDR_PANE_ID}" ;;
  working|idle|blocked)
           set -- report-agent --source swarm --agent claude --state "${state}" --seq "${seq}" --agent-session-id "${id}" "${HERDR_PANE_ID}" --
           while IFS= read -r a; do set -- "$@" "${a}"; done < "${SWARM_RESUME}" ;;
  *) exit 0 ;;
esac
"${h}" pane "$@" < /dev/null > /dev/null 2>&1 &
exit 0

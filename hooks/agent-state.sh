#!/bin/sh
# agent-state.sh <working|idle|blocked|release> — the plugin's Claude Code hooks, hooks/hooks.json:
# working on UserPromptSubmit and PostToolUse (a tool ran, so an answered permission prompt no longer
# blocks), idle on Stop, StopFailure (a turn that ended on an API error) and a cleared or resumed
# SessionStart, blocked on a permission Notification, release on SessionEnd. start_agent reports each
# agent's resume command to herdr with `pane report-agent --source swarm`, and each report here
# carries it again, with the session's current id (SWARM_RESUME, resume_file's argv, the id after
# --resume swapped), so whichever report herdr keeps, a restart resumes the session the agent is in.
# Every report has a --seq of the time in nanoseconds, so herdr keeps the newest whatever order the
# calls arrive in. release hands the pane back only when the user quits (SessionEnd's reason
# prompt_input_exit or logout): a herdr restart ends the session too, and a release then would drop
# the command that restores the agent. Only a swarm agent's session (SWARM_AGENT, set through
# --settings) in a herdr pane reports. herdr runs in the background, so a herdr that hangs never
# holds a prompt, and the hook always exits 0 and prints nothing, since a UserPromptSubmit hook's
# output reaches the agent's context.
# ponytail: a herdr that never answers leaves its call running; give it a timeout if one ever piles up.
input="$(cat)"
[ -n "${SWARM_AGENT:-}" ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0
h="${HERDR_BIN_PATH:-herdr}" state="$1"
(
  seq="$(python3 -c 'import time; print(time.time_ns())')" || exit 0
  case "${state}" in
    release) printf '%s' "${input}" | grep -Eq '"reason"[[:space:]]*:[[:space:]]*"(prompt_input_exit|logout)"' || exit 0
             exec "${h}" pane release-agent --source swarm --agent claude --seq "${seq}" "${HERDR_PANE_ID}" ;;
    working|idle|blocked) ;;
    *) exit 0 ;;
  esac
  id="$(printf '%s' "${input}" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  set -- "${HERDR_PANE_ID}"
  if [ -n "${id}" ]; then
    set -- --agent-session-id "${id}" "$@"
    if [ -f "${SWARM_RESUME:-}" ]; then
      set -- "$@" --; prev=""
      while IFS= read -r a; do
        [ "${prev}" != --resume ] || a="${id}"
        set -- "$@" "${a}"; prev="${a}"
      done < "${SWARM_RESUME}"
    fi
  fi
  exec "${h}" pane report-agent --source swarm --agent claude --state "${state}" --seq "${seq}" "$@"
) < /dev/null > /dev/null 2>&1 &
exit 0

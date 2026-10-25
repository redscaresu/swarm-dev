# shellcheck shell=bash
# lead-session.sh — sourced by the hooks that act only in the lead's session (lead-stop.sh,
# user-caught-reminder.sh), so both tell the lead apart the same way.

# lead_project <dir> — print the swarm project whose lead's session runs in <dir> (the session's cwd),
# or fail. The lead is no agent: an agent's environment has SWARM_AGENT (a Claude agent's, and a
# `claude -p` it runs) or SWARM_GH_CALLER (every agent's, launch_file's). It runs outside any
# worktree: a worktree's git dir is not the common one, and the user's own worktree sessions are not
# the lead either. And it is in a swarm project: $SWARM_PROJECT, else the nearest folder at or above
# <dir> with .claude/swarm/config, as find_project looks.
lead_project() {
  local dirs project
  [[ -z "${SWARM_AGENT:-}" && -z "${SWARM_GH_CALLER:-}" ]] || return 1
  dirs="$(git -C "$1" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)" \
    && [[ "${dirs%%$'\n'*}" != "${dirs#*$'\n'}" ]] && return 1
  if [[ -n "${SWARM_PROJECT:-}" ]]; then project="${SWARM_PROJECT}"
  else
    project="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
    while [[ "${project}" != / && ! -f "${project}/.claude/swarm/config" ]]; do project="$(dirname "${project}")"; done
  fi
  [[ -f "${project}/.claude/swarm/config" ]] || return 1
  printf '%s\n' "${project}"
}

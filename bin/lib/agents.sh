# shellcheck shell=bash

# bin/lib/panes.py: the one reader of this project's panes, shared by status, tidy and dash (each python
# imports it), so the three views agree.
#   pane_records(state, keep) yields (tab label, pane, recorded name) for each pane in keep (own_panes
#     and still live), from the tab records in STATE_DIR, skipping *.tmp; a pane's first record wins.
#   agent_state(a, name, s=None) -> (state, needs_a_look), where a is herdr's agent in the pane (None
#     for an empty pane) and s is session_state's answer for <name>: EMPTY (a start that failed),
#     then from the session: working (busy), idle, WAITING (waiting; s[1] says on what), unknown or
#     gone (both need a look). With no session (s None: codex, none recorded, or a retired
#     <name>-done, which has no agents.tsv line of its own), herdr's word: WAITING (blocked on a
#     prompt), working, retired (renamed by retire_agent), or herdr's own status.
#   session_state(log, name, listing) -> (state, waitingFor) from Claude Code's own list: the newest
#     agents.tsv (<log>) line for <name>, its session id, then that id's entry in <listing> (the
#     text of `claude agents --json`, None when the call failed). state is busy, idle, waiting (with
#     waitingFor, when the entry has it, on one line and cut to WHY_MAX characters), unknown (the
#     call failed, or a status it does not know) or gone (no entry for the recorded session, or one
#     with no status: Claude Code lists status only while the process is alive). None for an agent
#     herdr must answer for: codex, no line, or a session of '-' (session_id's None).
#   login_expired(log, name, projects) -> True when the last user or assistant entry in <name>'s
#     transcript (<projects>/*/<session>.jsonl, the file cost finds) is Claude Code's "Login expired ·
#     Please run /login": an assistant entry whose error field is authentication_failed. A prompt
#     after it (a resume sent) clears it; Claude Code's own user entries do not (is_prompt: isMeta, a
#     <task-notification>, "[Request interrupted by user]", a slash command such as /login run in its
#     pane and its <local-command-stdout>). A transcript that cannot be read is not
#     expired. Never the pane.
#   bg_running(log, name, projects) -> True when <name>'s transcript (as login_expired finds it) has a
#     background task it started (a tool result's backgroundTaskId, an async_launched agentId, or a
#     Monitor call's taskId; a task-list tool's taskId is none) with no <task-notification> for that
#     <task-id> carrying a <status> since: the session
#     waits on it, so its quiet pane is no stall. A check-in on a running shell has no <status> and
#     ends nothing. Sidechain entries are skipped. A transcript that cannot be read has none.
#   usage_limit(text) -> ("dialog", <option>) when the pane text, after its last reply (⏺ or ●), ends on
#     Claude Code's live usage-limit dialog: its option lines ("Stop and wait for limit to reset" /
#     "<option>. Wait here, then continue automatically") among the last USAGE_TAIL non-empty lines,
#     with no prompt line (an input box) under them, so a prompt quoting the dialog is none;
#     ("waiting", "") when it waits after that choice ("Usage limit reached" with "Continuing shortly"
#     or "limit resets"); else None. pane_text(pane) is herdr's agent read.
#   shown_state(a, name, s, log, projects) -> agent_state, except that an idle Claude agent whose
#     login expired is (auth, True): only the user's /login clears it, so it needs them, never idle;
#     and a working, idle or waiting agent whose pane is on the usage-limit dialog, or a working or
#     waiting one whose pane waits after it, is (usage-limit, False): an idle one under the waiting
#     line is idle.
#     For the views (status, dash); wait reads login_expired itself.

# bin/lib/stall.py: the one stall rule and agent-to-story mapping, shared by dash and `wait --stall` (each
# python imports it). herdr gives no time an agent entered its state, so a
# builder's last sign of life stands in for it.
#   story_for(name, stories) -> the slug whose agent is <name> (cut at 32 characters, any -doneN
#     dropped), preferring a story not done; stories are (slug, agent name, status). None if none.
#   sign_time(f) -> an events.tsv line's (fields) epoch when it is a sign of life, else None. A
#     nudge is not one, so `nudge` and `resume` (wait's) and `tell:nudge` (the lead's) lines are skipped, as are
#     `tell:note` lines (a note the lead left a conductor says nothing about whether it works), and so
#     is any other tell whose outcome is not ok: it never reached the builder. A `board-pr:<step>`
#     line is the lead's board edit, whose name may be a story's slug, so it is never one either, and
#     nor is a `usage-limit` line (wait's, about the agent) or an `incident` line, which wait and close write about the agent, not the agent itself.
#   last_seen(events) -> {target: epoch} of each target's newest sign_time line, read once.
#   stall_age(seen, slug, name, signs, now) -> minutes before now (default: the clock) of the newest
#     of: seen[slug] or seen[name] (started, findings sent ...) and each of signs: epoch seconds (a
#     worktree's last commit or edit, an agent's newest own work in its session log or its subagents'
#     logs, the time a wait began) or ISO times (a PR's updatedAt). None when there is no sign at all.
#   A working builder whose stall_age reaches stall_minutes is stalled?.

# own_panes — the herdr panes this project opened (next_pane records "<pane> [name]" per tab in
# STATE_DIR). herdr lists every project's agents; a pane id says which are this project's.
# Only lines shaped like a tab record ("<pane> [name]", a pane id like w1:p6K) count: STATE_DIR also
# holds codex briefs, watch-seen and .tmp files, and a list of those to skip would fail open. Only
# regular files are read, since it may also hold a directory, and it always succeeds: a cat that
# failed on a directory used to fail it under pipefail, so a caller reading its status saw none.
own_panes() {
  local f
  for f in "${STATE_DIR}"/*; do
    if [[ -f "${f}" ]]; then cat "${f}" 2>/dev/null || true; fi
  done | awk 'NF <= 2 && $1 ~ /^[A-Za-z0-9]+:[A-Za-z0-9]+$/ {print $1}'
}

require_herdr() { [[ "${HERDR_ENV:-}" == 1 ]] || die "not running inside a herdr pane (HERDR_ENV != 1)"; }

# require_trusted <cwd> — stop unless Claude Code already trusts <cwd>. In an untrusted folder,
# Claude Code opens its "do you trust this folder?" prompt, and the agent stalls there unseen.
# Claude Code keys trust on the git root, and for a worktree on its main checkout, so a new story
# worktree is covered once its repo is trusted. Outside git, a trusted ancestor covers it. Trust
# lives in ~/.claude.json, which every running session rewrites, so this only reads it; if the
# file cannot be read, the start goes ahead.
require_trusted() {
  local cwd="$1" in_git="" root gitdir common
  if root=$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null); then
    in_git=git
    # A linked worktree's git dir differs from the shared one: trust is keyed on the main checkout.
    # A submodule's are the same (.git/modules/<name>), so it keeps its own top level.
    gitdir=$(git -C "${cwd}" rev-parse --path-format=absolute --git-dir)
    common=$(git -C "${cwd}" rev-parse --path-format=absolute --git-common-dir)
    [[ "${gitdir}" == "${common}" ]] || root="$(dirname "${common}")"
  else
    root="$(cd "${cwd}" && pwd -P)"
  fi
  python3 "${SWARM_HOME}/bin/lib/require_trusted.py" "${root}" "${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json" "${in_git}" \
    || die "Claude Code does not trust ${root} yet, so the agent would stall on its trust prompt. Run claude in ${root} once, accept the prompt, then try again."
}

# MIN_CLAUDE: the oldest Claude Code with both `--session-id` and `claude agents --json`, which every
# Claude agent's state is read through (pinned by experiment; README's Requirements names it too).
MIN_CLAUDE=2.1.145
# shellcheck disable=SC2034 # read in another file
GOAL_MIN_CLAUDE=2.1.269   # the oldest with /goal, which goal = N needs (the epic's floor; the spike ran 2.1.299)
CLAUDE_CHECKED=""   # set once require_claude passes, so a run checks once

# require_claude [min] — stop unless the installed Claude Code is <min> (default MIN_CLAUDE) or later
# (`claude --version` prints `2.1.145 (Claude Code)`). When the caller is a Claude session herdr knows (the pane it runs
# in), that session must also be in Claude Code's own list (require_listed), or the readers would
# find no agent there. From a plain shell with no session, only the version is checked. Once a
# check passes, later calls in the same run return at once: `story` checks before its worktree (with
# goal on, for GOAL_MIN_CLAUDE), then start_agent asks again.
# shellcheck disable=SC2120 # another file's callers pass it
require_claude() {
  local min="${1:-${MIN_CLAUDE}}" have session
  [[ -z "${CLAUDE_CHECKED:-}" ]] || return 0
  command -v claude >/dev/null || die "Claude Code (claude) is not on PATH; swarm.sh needs ${min} or later."
  have="$(claude --version 2>/dev/null)" || have=""
  version_at_least "${have}" "${min}" \
    || die "swarm.sh needs Claude Code ${min} or later, and claude --version says '${have%%$'\n'*}'. Update it (claude update), then try again."
  session="$(session_for_pane "${HERDR_PANE_ID:-}")"
  [[ -z "${session}" ]] || require_listed "${session}"
  CLAUDE_CHECKED=1
}

# version_at_least <text> <min> — succeed when <text> starts (after any blanks) with an x.y.z that is
# <min> or later; fail when it is older or <text> starts with anything else, such as a warning that
# names another version.
version_at_least() {
  python3 -I -c '
import re, sys
m = re.match(r"\s*(\d+)\.(\d+)\.(\d+)", sys.argv[1])
sys.exit(0 if m and tuple(map(int, m.groups())) >= tuple(map(int, sys.argv[2].split("."))) else 1)' "$1" "$2"
}

# MIN_HERDR: the oldest herdr that keeps the resume command an agent reports (0.9.2's release notes).
# An older one takes the report and drops the command, so a restart would bring the agent back
# without its guards.
MIN_HERDR=0.9.2
HERDR_CHECKED=""   # set once require_herdr_version passes, so a run checks once

# require_herdr_version — stop unless herdr --version (`herdr 0.9.5`) names MIN_HERDR or later; one
# that names no version stops it too.
require_herdr_version() {
  local have
  [[ -z "${HERDR_CHECKED}" ]] || return 0
  have="$(herdr --version 2>/dev/null)" || have=""
  version_at_least "${have#herdr }" "${MIN_HERDR}" \
    || die "swarm.sh needs herdr ${MIN_HERDR} or later, or a restart brings agents back without their guards, and herdr --version says '${have%%$'\n'*}'. Update it (herdr update), then try again."
  HERDR_CHECKED=1
}

# require_listed <session> — stop unless <session> is in claude agents --json. A list that cannot be
# read stops too, and says so (its first error line, or what it printed instead of a JSON list).
require_listed() {
  local err list rc=0 why found
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-agents.XXXXXX")" || die "could not make a temporary file to read claude agents --json"
  list="$(claude_agents "${err}")" || rc=$?
  why="$(head -1 "${err}")"; rm -f "${err}"
  [[ ${rc} -eq 0 ]] || die "could not read claude agents --json (${why:-it exited ${rc}}), so this session (${1}) cannot be found in it. Check that the command works here, then try again."
  found="$(printf '%s' "${list}" | python3 -c '
import json, sys
text = sys.stdin.read()
try:
    entries = json.loads(text)
except ValueError:
    entries = None
if not isinstance(entries, list):
    print("empty output" if not text.strip() else "not a JSON list")
else:
    print("yes" if any(isinstance(e, dict) and e.get("sessionId") == sys.argv[1] for e in entries) else "no")' "$1")" || found=""
  case "${found}" in
    yes) ;;
    no) die "this session (${1}) is not in claude agents --json: the interactive listing every agent's state is read from is missing. Restart Claude Code on ${MIN_CLAUDE} or later, then try again." ;;
    *) die "could not read claude agents --json (${found:-python3 could not parse it}), so this session (${1}) cannot be found in it. Check that the command works here, then try again." ;;
  esac
}

# next_pane <tab-label> <cwd> — a fresh shell pane in a tab with room, creating tabs as needed.
# prune_dead_panes <state> — drop the panes herdr no longer has (closed by hand), so the next split
# targets a live pane. Left alone when herdr cannot list its panes.
prune_dead_panes() {
  local live
  live=$(herdr pane list 2>/dev/null | json "' '.join(p['pane_id'] for p in d['result']['panes'])" 2>/dev/null) || return 0
  awk -v live=" ${live} " 'index(live, " " $1 " ")' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

next_pane() {
  local label="$1" cwd="$2" name="${3:-}" n=1 state panes count pane
  mkdir -p "${STATE_DIR}"
  while :; do
    local tab_label="${label}"; [[ ${n} -gt 1 ]] && tab_label="${label}-${n}"
    state="${STATE_DIR}/${tab_label}"
    [[ -f "${state}" ]] && prune_dead_panes "${state}"
    count=0; [[ -f "${state}" ]] && count=$(wc -l < "${state}" | tr -d ' ')
    if [[ ${count} -lt ${PANES_PER_TAB} ]]; then
      if [[ ${count} -eq 0 ]]; then
        pane=$(herdr tab create --workspace "${HERDR_WORKSPACE_ID}" --cwd "${cwd}" --label "${tab_label}" --no-focus \
          | json "d['result']['root_pane']['pane_id']")
      else
        # 2x2: 2nd splits the first to the right, 3rd splits the first down, 4th splits the second down.
        read -r -a panes <<< "$(awk '{ print $1 }' "${state}" | tr '\n' ' ')"
        case ${count} in
          1) pane=$(herdr pane split "${panes[0]}" --direction right --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          2) pane=$(herdr pane split "${panes[0]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          3) pane=$(herdr pane split "${panes[1]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
        esac
      fi
      [[ -n "${pane}" ]] || die "herdr could not open a pane in tab ${tab_label}"
      [[ -z "${name}" ]] || herdr pane rename "${pane}" "${name}" >/dev/null 2>&1 || true
      echo "${pane}${name:+ ${name}}" >> "${state}"
      echo "${pane}"
      return
    fi
    n=$((n + 1))
  done
}

# AGENT_ENV: the variables every agent starts with besides those AGENT_PREFIXES name (the locale,
# swarm.sh's own SWARM_* settings, SWARM_PROJECT as PROJECT_DIR, absolute, and the XDG_* directories),
# each with swarm.sh's own value when it has one: the env-allowlist spike's (herdr 0.9.1); where
# claude, codex, gh, git and gpg keep their logins, config and logs; the session bus, through which
# gh's keyring token and git-credential-libsecret reach the Secret Service on Linux; the ssh agent's
# socket and git's ssh command, so a push works; the proxy and CA settings, so an agent behind a
# proxy or an intercepting CA reaches GitHub; and which provider and model Claude Code uses (Bedrock,
# Vertex, Foundry), whose credentials come from the provider's own login or profile files. Settings
# and paths, not secrets (a proxy URL with a password in it passes too). Any other variable reaches
# an agent only by name, through a story's env: (story_env). AGENT_SET are the ones swarm.sh sets for
# every agent itself (launch_file).
AGENT_ENV="PATH HOME TERM USER LOGNAME TMPDIR LANG CLAUDE_CONFIG_DIR CLAUDE_PROJECTS_DIR CODEX_HOME GH_CONFIG_DIR GIT_CONFIG_GLOBAL GNUPGHOME DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK GIT_SSH_COMMAND HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy SSL_CERT_FILE NODE_EXTRA_CA_CERTS CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL AWS_REGION AWS_PROFILE CLOUD_ML_REGION ANTHROPIC_VERTEX_PROJECT_ID"
AGENT_PREFIXES="LC_ SWARM_ XDG_"
AGENT_SET="SHELL ZDOTDIR GPG_TTY"
# HERDR_PANE_ENV: herdr's variables for a pane, which the agent's swarm.sh and herdr's hooks read.
# Only the new pane's shell has its values, so the launch line names them and that shell expands them.
HERDR_PANE_ENV="HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH"
# AGENT_SHELL: what the pane runs once its environment is clean, and (its first word) the agent's
# SHELL. No rc file, which could export a secret again. SWARM_AGENT_SHELL overrides it, for tests.
# ponytail: zsh as the spike ran it; a Linux pane with no /bin/zsh needs another shell here.
AGENT_SHELL="${SWARM_AGENT_SHELL:-/bin/zsh -f}"
ENV_READY="swarm: agent environment ready"

# story_env <story> — the names under its env:, a one-line [A, B] list (quotes, commas and a trailing
# # comment gone). A story holds names, never values. Refused, with the reason printed and 1
# returned: any other form (a block list, a list over several lines, a bare name), which would read
# as no names or the wrong ones; a name that is not [A-Z_][A-Z0-9_]*; a reserved one (reserved_env);
# and one swarm.sh's environment does not have, without which the builder would fail later and burn
# an attempt. A conductor has only the names its stories had when it started, so that refusal says
# how one picks up a story's new name.
story_env() {
  local v n words out="" exported list='^\[[^][]*\]$' epic
  v="$(get_fm "$1" env)"; v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"
  # An empty env: is no names, unless - items follow it (a block list, at any indent).
  if { [[ -n "${v}" ]] && [[ ! "${v}" =~ ${list} ]]; } || { [[ -z "${v}" ]] && awk '/^---$/ && ++n == 2 { exit }
      n == 1 && bare && /^[ \t]*-([ \t]|$)/ { f = 1; exit } n == 1 { bare = /^env:[ \t]*(#.*)?$/ } END { exit !f }' "$1"; }; then
    echo "$1: env: is not a one-line list; write it as env: [NAME, ...]"; return 1
  fi
  v="${v#\[}"; v="${v%\]}"; v="${v//,/ }"; v="${v//\"/}"; v="${v//\'/}"
  read -r -a words <<< "${v}"   # read, not a bare word list, so a * is never globbed
  exported=" $(compgen -e | tr '\n' ' ') "   # the environment only, never swarm.sh's own variables
  for n in ${words[@]+"${words[@]}"}; do
    [[ "${n}" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { echo "$1: env: '${n}' is not a variable name ([A-Z_][A-Z0-9_]*)"; return 1; }
    ! reserved_env "${n}" \
      || { echo "$1: env: ${n} is reserved: every agent gets it already, herdr or the lead's own session sets it, or it loads code, so a story cannot name it"; return 1; }
    [[ "${exported}" != *" ${n} "* ]] || { out+=" ${n}"; continue; }
    epic="$(fm "$1" epic)"
    echo "$1: env: ${n} is not set here, so its builder would start without it. Export it in the session that runs swarm.sh, then try again. A conductor has only the names its stories had when it started: if one runs this, the lead restarts it with \`swarm.sh conduct ${epic:---backlog}\` so it picks the name up"
    return 1
  done
  printf '%s' "${out# }"
}

# reserved_env <name> — true for a name a story cannot add: one every agent gets already (AGENT_ENV,
# AGENT_SET, AGENT_PREFIXES), herdr's (HERDR_*), the lead's own Claude Code session's (CLAUDECODE,
# CLAUDE_CODE_*, CLAUDE_PID), and one that loads code into what the agent runs (BASH_ENV, ENV, DYLD_*,
# LD_*).
reserved_env() {
  local p
  [[ " ${AGENT_ENV} ${AGENT_SET} " != *" $1 "* ]] || return 0
  for p in ${AGENT_PREFIXES}; do [[ "$1" != "${p}"* ]] || return 0; done   # loose-match: ok AGENT_PREFIXES are prefixes by design
  case "$1" in HERDR_*|CLAUDECODE|CLAUDE_CODE_*|CLAUDE_PID|BASH_ENV|ENV|DYLD_*|LD_*) return 0 ;; esac
  return 1
}

# launch_file <file> <names> <marker> <zdotdir> — write clean_env's wrapper: it deletes itself,
# exports AGENT_ENV, AGENT_PREFIXES' variables and <names> with swarm.sh's values, sets AGENT_SET
# (GPG_TTY to the pane's own terminal, so pinentry asks there, never in the lead's), unsets the
# HERDR_PANE_ENV variables the pane left empty (so a ${NAME-default} applies), prints <marker>, and
# execs AGENT_SHELL. SHELL is AGENT_SHELL's zsh and ZDOTDIR <zdotdir>
# (clean_env's, empty), so every shell the agent starts later (Claude Code's Bash tool, codex's
# commands) is that zsh, and it reads its user startup files, and Claude Code its snapshot's .zshrc,
# from there: never ~/.bashrc, ~/.bash_profile or HOME's zsh files, which could export a secret
# again. 0600, made by its owner alone.
launch_file() {
  local exported n v
  exported=" $(compgen -e | tr '\n' ' ') "
  mkdir -p "${1%/*}"; rm -f "$1"
  (umask 077; {
    printf '/bin/rm -f -- %q\n' "$1"
    for n in ${AGENT_ENV} $(compgen -e | grep -E "^(${AGENT_PREFIXES// /|})" || true) $2; do   # loose-match: ok AGENT_PREFIXES are env name prefixes, a regex alternation
      [[ "${exported}" == *" ${n} "* ]] || continue
      v="${!n}"; [[ "${n}" != SWARM_PROJECT ]] || v="${PROJECT_DIR}"   # resolved, so a relative one holds from any cwd
      printf 'export %s=%q\n' "${n}" "${v}"
    done
    printf 'export SHELL=%q ZDOTDIR=%q\n' "${AGENT_SHELL%% *}" "$4"
    # The agent's name (its ZDOTDIR's): gh-shim logs its calls under it, and not as the starting
    # command's (its SWARM_GH_VIA, which only swarm.sh's own calls carry).
    printf 'export SWARM_GH_CALLER=%q\nunset SWARM_GH_VIA\n' "${4##*/}"
    # shellcheck disable=SC2016 # the wrapper's own bash expands them
    printf '%s\n' 't="$(tty 2>/dev/null)" && export GPG_TTY="${t}"' \
      "for n in ${HERDR_PANE_ENV}; do [ -n \"\${!n}\" ] || unset \"\${n}\"; done"
    printf 'echo %q\nexec %s\n' "$3" "${AGENT_SHELL}"
  } > "$1")
}

# ZDOT_ENV, ZDOT_PROFILE: the .zshenv and .zprofile in an agent's own ZDOTDIR (clean_env), written
# again whenever a restart restores the agent (resume_file's wrapper).
# shellcheck disable=SC2016 # the agent's zsh expands them
ZDOT_ENV='__swarm_path="${PATH}"' ZDOT_PROFILE='[[ -z "${__swarm_path}" ]] || export PATH="${__swarm_path}"'

# clean_env <pane> <name> <names> [keep] — before an agent starts in <pane>, its shell swaps itself through
# env -i for launch_file's wrapper. herdr passes no env and the agent inherits the pane's shell, which
# holds the user's whole environment. The wrapper is a 0600 file under .swarm/launch, so no value
# reaches argv, herdr's typed line or the scrollback. story_env has checked <names>. A shell that
# never takes it closes the pane, unless keep: upgrade's restart, where the pane is the agent's own.
clean_env() {
  local pane="$1" base="${PROJECT_DIR}/.swarm/launch/$2" zdot="${PROJECT_DIR}/.swarm/zdotdir/$2" n line out try marker typed=""
  # The agent's own ZDOTDIR, made afresh and 0700, so nothing an earlier agent wrote there runs. A
  # login shell runs /etc/zprofile between .zshenv and .zprofile, and its path_helper (macOS) puts
  # /usr/bin and /bin ahead of the lead's own git, python3 and bash: .zshenv keeps the PATH the shell
  # was given, and .zprofile puts it back. Neither holds a value, and a shell that is not a login one
  # keeps its PATH as it came.
  rm -rf "${zdot}"
  (umask 077; mkdir -p "${zdot}"; printf '%s\n' "${ZDOT_ENV}" > "${zdot}/.zshenv"; printf '%s\n' "${ZDOT_PROFILE}" > "${zdot}/.zprofile")
  # A freshly split pane is not always ready (as for agent start): retry a failed run once. A failed
  # run may still have typed its line, so each try has its own wrapper and marker, and the wait is for
  # the last one's: two typed lines run both wrappers in turn, and the second leaves the clean shell.
  for try in 1 2; do
    marker="${ENV_READY} $$.${try}"
    launch_file "${base}.${try}" "$3" "${marker}" "${zdot}"
    line="exec /usr/bin/env -i HERDR_ENV=1"
    for n in ${HERDR_PANE_ENV}; do line+=" ${n}=\"\$${n}\""; done
    line+=" /bin/bash $(printf '%q' "${base}.${try}")"
    if out="$(herdr pane run "${pane}" "${line}" 2>&1)"; then typed=1; break; fi
    [[ ${try} -eq 2 ]] || nap 3
  done
  if [[ -z "${typed}" ]] || ! out="$(herdr pane wait-output "${pane}" --match "${marker}" --timeout 30000 2>&1)"; then
    rm -f "${base}.1" "${base}.2"
    [[ -n "${4:-}" ]] || herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
    die "$2: the pane's shell did not take the agent's environment: ${out}"
  fi
  rm -f "${base}.1" "${base}.2"   # gone already, unless a shell never ran one
}

# resume_refusal <arg>... — when herdr would refuse <arg>... as a resume command, print why and
# succeed: more than 64 arguments or 8 KiB (the command joined, a separator between arguments), or
# an argument with an apostrophe or a control character (herdr's rules; its first word, python3, is a
# plain command name).
resume_refusal() {
  local a opt="" bytes
  [[ $# -le 64 ]] || { echo "$# arguments, more than 64"; return 0; }
  bytes="$(printf '%s' "$*" | LC_ALL=C wc -c | tr -d ' ')"
  [[ ${bytes} -le 8192 ]] || { echo "${bytes} bytes, more than 8 KiB"; return 0; }
  for a in "$@"; do
    [[ "${a}" != --* ]] || opt="${a}"
    [[ "${a}" != *"'"* ]] || { echo "${opt:-$1} ${a} has an apostrophe"; return 0; }
    [[ "${a}" != *[[:cntrl:]]* ]] || { echo "${opt:-$1} has a control character"; return 0; }
  done
  return 1
}

# RESUME_DIR: resume_file's files, one pair per Claude session. Outside the project, so its path,
# which may hold an apostrophe herdr refuses, is never in a resume command.
RESUME_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/swarm-dev/resume"

# resume_file <name> <session> <names> <arg>... — what herdr runs to resume agent <name> (Claude
# session <session>) after a restart, in RESUME_DIR: <session>.argv, its resume command <arg>... one
# argument a line, whose --resume the plugin's hooks keep at the pane's own session and attach to
# each report (SWARM_RESUME); and <session>.py, the wrapper that command starts with (python3 -I
# <wrapper> claude --resume ...). A restored pane's shell holds the user's whole environment, so the
# wrapper keeps only the variables clean_env's agent starts with (AGENT_ENV, AGENT_PREFIXES', herdr's
# and <names>), with the restored pane's own values, so no value is written down or put on a command
# line; sets AGENT_SET as launch_file does, with SWARM_PROJECT, SWARM_RESUME and gh-shim's
# SWARM_GH_LOG and SWARM_GH_CALLER (its folder first on PATH, so the agent's gh calls log; no
# SWARM_GH_VIA); and execs its arguments. Python, not bash, so neither a BASH_ENV nor an exported
# function in that environment runs before the scrub or changes it, as none can on a first start through env -i. It also makes the
# session's own ZDOTDIR (<session>.zdotdir) afresh at 0700 with clean_env's two files, so nothing
# written there since runs in the restored agent's shells; it empties the folder rather than
# removing it, so two restores at once both finish, and a folder that is not this user's, or holds
# anything else once made, stops the restore before claude starts. Both files 0600,
# and like that folder a session's own, so a later agent of the same name, or its restore, never
# changes them.
resume_file() {
  local name="$1" session="$2" names="$3"
  shift 3
  mkdir -p "${RESUME_DIR}"
  (umask 077
    printf '%s\n' "$@" > "${RESUME_DIR}/${session}.argv"
    python3 -I - "${RESUME_DIR}/${session}.py" "HERDR_ENV ${HERDR_PANE_ENV} ${AGENT_ENV} ${names}" "${AGENT_PREFIXES}" \
      "${HERDR_PANE_ENV}" "${PROJECT_DIR}" "${RESUME_DIR}/${session}.argv" "${AGENT_SHELL%% *}" "${RESUME_DIR}/${session}.zdotdir" \
      "${ZDOT_ENV}" "${ZDOT_PROFILE}" "${name}" "${SWARM_GH_LOG:-}" "${SWARM_HOME}/bin/gh-shim" <<'PY'
import sys
path, keep, prefixes, pane, project, resume, shell, zdotdir, zshenv, zprofile, name, gh_log, gh_shim = sys.argv[1:]
open(path, "w").write(f"""# swarm.sh's restore wrapper (resume_file): the session's ZDOTDIR made afresh, as clean_env makes an
# agent's, and its allowlisted environment, then its arguments.
import os, shutil, stat, sys
z = {zdotdir!r}
old = os.umask(0o077)
try:
    os.mkdir(z, 0o700)
except FileExistsError:
    pass
st = os.lstat(z)
if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
    sys.exit("swarm: " + z + " is not a folder of this user's, so the agent is not restored")
os.chmod(z, 0o700)
for e in os.listdir(z):
    p = os.path.join(z, e)
    if os.path.isdir(p) and not os.path.islink(p):
        shutil.rmtree(p, ignore_errors=True)
    else:
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass
for f, text in ((".zshenv", {zshenv!r}), (".zprofile", {zprofile!r})):
    with os.fdopen(os.open(os.path.join(z, f), os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600), "w") as out:
        out.write(text + "\\n")
if set(os.listdir(z)) - {{".zprofile", ".zshenv"}}:
    sys.exit("swarm: " + z + " holds more than its two files, so the agent is not restored")
os.umask(old)
keep = {sorted(set(keep.split()))!r}
env = {{k: v for k, v in os.environ.items() if k in keep or k.startswith({tuple(prefixes.split())!r})}}
env.update(SWARM_PROJECT={project!r}, SWARM_RESUME={resume!r}, SHELL={shell!r}, ZDOTDIR={zdotdir!r},
           SWARM_GH_LOG={gh_log!r}, SWARM_GH_CALLER={name!r}, PATH=":".join(p for p in ({gh_shim!r}, env.get("PATH", "")) if p))
env.pop("SWARM_GH_VIA", None)
try:
    env["GPG_TTY"] = os.ttyname(0)
except OSError:
    pass
for n in {pane.split()!r}:
    if not env.get(n):
        env.pop(n, None)
os.execvpe(sys.argv[1], sys.argv[1:], env)
""")
PY
  ) || die "${name}: could not write its restore wrapper in ${RESUME_DIR}"
}

# agent_cmd <tab> <name> <cwd> <role> <prompt-file> [pane-name] — `swarm.sh agent`: start_agent, with
# the story's env: names (story_env) when it starts a builder of a story on the board (<name> is the
# story's slug and <role> a building one), as a conductor's restart of a stacked child does.
agent_cmd() {
  local names="" story="${BOARD}/stories/${2:-}.md"
  if [[ -f "${story}" && " ${BUILDER_ROLES} " == *" ${4:-} "* ]]; then names="$(story_env "${story}")" || die "${names}"; fi
  start_agent "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-${2:-}}" "${names}"
}

# start_agent <tab> <name> <cwd> <role> <prompt-file> [pane-name] [env-names] [model] — an agent in a
# fresh pane with a clean environment (clean_env), plus the variables <env-names> names, which its
# caller has checked with story_env. Never read from the environment, where any value could stand in.
# [model] runs <role> on another model than its policy's, at its policy's effort (step_up's rung).
start_agent() {
  local tab="$1" name cwd="$3" role="$4" prompt_file="$5" pane_name="${6:-$2}" names="${7:-}" kind model effort pane
  name="$(agent_name "$2")"   # the one place names are mapped, so `wait <same name>` always finds it
  [[ -f "${prompt_file}" ]] || die "no prompt file ${prompt_file}"
  read -r kind model effort <<< "$(policy "${role}")"
  model="${8:-${model}}"   # a step-up's rung: the role's family on another model
  # Before the pane opens, so a refusal leaves no empty pane behind. A claude agent's session id is
  # minted here, once, so a retry reuses it and agents.tsv holds it from the start; codex has none.
  local session=- flags=() resume=()
  # SWARM_RESUME: where the plugin's hooks find a Claude agent's resume command (resume_file).
  # clean_env passes it on with every SWARM_ variable, so it is never on a command line; empty for codex.
  local -x SWARM_RESUME=""
  if [[ "${kind}" == claude ]]; then
    require_trusted "${cwd}"
    # shellcheck disable=SC2119 # takes no argument here
    require_claude
    require_herdr_version
    session="$(python3 -I -c 'import uuid; print(uuid.uuid4())')" || die "${name}: could not mint a session id (python3)"
    SWARM_RESUME="${RESUME_DIR}/${session}.argv"
    # No agent can run `gh pr merge`, a conductor with merge = agent included: it merges through
    # swarm.sh merge, whose gh the guard never reaches. `gh api` could still merge, so the briefs say it too.
    # The session's env goes through --settings, since herdr passes no env. SWARM_AGENT tells the
    # plugin's guard hook the session is an agent's, kept out of the main checkout (hooks/merge-guard.sh).
    # builder_subagent_model: without _FORCE the model setting leaves an Explore subagent on the
    # parent's model (opusplan-spike).
    local env=(SWARM_AGENT "${name}") deny=("Bash(gh pr merge:*)") settings why
    # The fallback reviewer stands in for codex's read-only sandbox: no file tools, no commit or push.
    [[ "${role}" != review-fallback ]] || deny+=(Edit Write NotebookEdit "Bash(git commit:*)" "Bash(git push:*)")
    [[ -n "${CFG_builder_subagent_model}" && " ${BUILDER_ROLES} " == *" ${role} "* ]] \
      && env+=(CLAUDE_CODE_SUBAGENT_MODEL "${CFG_builder_subagent_model}" CLAUDE_CODE_SUBAGENT_MODEL_FORCE 1)
    settings="$(python3 -I -c 'import json, sys; a = sys.argv[1:]; print(json.dumps({"env": dict(zip(a[::2], a[1::2]))}, separators=(",", ":")))' "${env[@]}")" \
      || die "${name}: could not write its --settings (python3)"
    flags=(--model "${model}" --effort "${effort}" --permission-mode auto --disallowedTools "${deny[@]}" --settings "${settings}")
    # What herdr runs to resume the agent after a restart: resume_file's wrapper, then claude as it started.
    resume=(python3 -I "${RESUME_DIR}/${session}.py" claude --resume "${session}" "${flags[@]}")
    why="$(resume_refusal "${resume[@]}")" \
      && die "${name}: herdr would refuse the command that resumes the agent after a restart: ${why}"
  fi
  free_agent_name "${name}"
  rm -f "${PANE_DIR:?}/${name}"   # the last holder's pane record (pane_check), which a retired one took along
  # Once the name is free, so a start refused there leaves no resume files behind.
  [[ "${kind}" != claude ]] || resume_file "${name}" "${session}" "${names}" "${resume[@]}"
  pane=$(next_pane "${tab}" "${cwd}" "${pane_name}")
  clean_env "${pane}" "${name}" "${names}"
  # A freshly split pane is not always an available shell yet (agent_pane_busy): retry once.
  local try out
  for try in 1 2; do
    if [[ "${kind}" == codex ]]; then
      # No update check: codex's startup prompt to upgrade takes the pane, and the brief then
      # lands in a bare shell. A planning codex must write its one answer file, and read-only made it
      # ask the user for every write: it runs workspace-write rooted (-C) at its tab's output dir, so
      # it reads as before and writes only there. Any other tab stays read-only. Hooks off: codex
      # opens a review dialog for an untrusted hook (herdr's, ~/.codex/hooks.json) when the brief
      # starts the session, and the brief is lost behind it. Off trusts nothing; none runs here.
      local sandbox=(-s read-only) dir
      dir="$(codex_out_dir "${tab}")"
      if [[ -n "${dir}" ]]; then mkdir -p "${dir}"; sandbox=(-s workspace-write -C "${dir}"); fi
      out=$(herdr agent start "${name}" --kind codex --pane "${pane}" --timeout 60000 -- \
        "${sandbox[@]}" -c features.hooks=false -c "model_reasoning_effort=\"${effort}\"" -c check_for_update_on_startup=false 2>&1) && break
    else
      out=$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- \
        --session-id "${session}" "${flags[@]}" 2>&1) && break
    fi
    if [[ ${try} -eq 2 ]]; then
      # Close the pane rather than leave an empty shell; next_pane prunes it from the tab record.
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "${name}: herdr could not start the agent: ${out}"
    fi
    nap 3
  done
  # herdr resumes a Claude pane with `claude --resume <id>` alone, which drops every flag above, the
  # guards included, in the pane's whole environment. Reporting the whole command makes a restart
  # resume the agent as it started. As soon as herdr has started it, before the brief, so a pane
  # whose brief is never taken up still has it; as idle, which it is, with the time as its --seq, so
  # the plugin's hooks (hooks/agent-state.sh, which attach the same command) report over it from the
  # brief on. The agent has done nothing yet, so a refusal closes its pane and stops the start.
  local seq
  if [[ "${kind}" == claude ]]; then
    seq="$(python3 -I -c 'import time; print(time.time_ns())')" || seq=""
    if [[ -z "${seq}" ]] || ! out=$(herdr pane report-agent "${pane}" --source swarm --agent claude --state idle \
        --seq "${seq}" --agent-session-id "${session}" -- "${resume[@]}" 2>&1); then
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "${name}: herdr did not take the command that resumes the agent, so a restart would drop its guards: ${out:-could not read the clock (python3)}"
    fi
  fi
  # Before the brief, so an agent whose brief is not taken up is still on record.
  record_agent "${role}" "${name}" "${kind}" "${model}" "${effort}" "${session}"
  if [[ "${kind}" == codex && -n "$(codex_out_dir "${tab}")" ]]; then
    # Its working directory is the output dir, so say where the brief's relative paths start.
    local brief="${STATE_DIR}/brief-${name}.md"
    mkdir -p "${STATE_DIR}"
    { echo "The project is ${PROJECT_DIR}; every relative path below is relative to it. You can write only in $(codex_out_dir "${tab}")."; echo; cat "${prompt_file}"; } > "${brief}"
    prompt_file="${brief}"
  fi
  # Fable's brief gets SLOW_PROMPT_TIMEOUT_MS in all: herdr's wait stays as it is, and longer reads
  # after it make each of deliver_prompt's two tries half of it. Local, so a later prompt keeps the default.
  local SETTLE_READS="${SETTLE_READS}"
  [[ "${model}" != fable || -n "${SWARM_PROMPT_TIMEOUT_MS:-}" ]] \
    || SETTLE_READS=$(((SLOW_PROMPT_TIMEOUT_MS / 2 - PROMPT_TIMEOUT_MS) / 5000))
  deliver_prompt "${name}" "${prompt_file}" "${pane}"
  echo "${name} ${pane} ${kind}:${model}:${effort}"
}

# codex_out_dir <tab> — where a planning tab's agents write their answers: .swarm/<epic> for
# scope-<epic>, .swarm/<hld> for plan-<hld>; empty for any other tab.
codex_out_dir() {
  case "$1" in
    scope-?*) echo "${PROJECT_DIR}/.swarm/${1#scope-}" ;;
    plan-?*) echo "${PROJECT_DIR}/.swarm/${1#plan-}" ;;
  esac
}

# CLAUDE_PROJECTS: Claude Code's per-project folders (session transcripts, memory), read by cost, outcomes
# and wait's login_expired.
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/projects}"

# AGENTS_LOG: one line per agent started (date, role, name, kind, model, effort, session), so
# `cost` can attribute every token to a role. Beside state/, not in it: state/ holds tab records.
AGENTS_LOG="${PROJECT_DIR}/.swarm/agents.tsv"

# SESSIONS_DIR: archive_session's gzip copies of closed agents' session logs, which cost and outcomes
# read once Claude Code has deleted the original.
# shellcheck disable=SC2034 # read in another file
SESSIONS_DIR="${PROJECT_DIR}/.swarm/sessions"

# session_for_pane <pane> — the Claude session id herdr reports for the agent in <pane>, or nothing.
session_for_pane() {
  herdr agent list 2>/dev/null | json "next(((a.get('agent_session') or {}).get('value','') for a in d['result']['agents'] if a.get('pane_id')=='$1'),'')" 2>/dev/null || true
}

# claude_agents [err-file] — Claude Code's own list of its sessions, as JSON; fails when it cannot be
# read. Its errors go to <err-file>, else nowhere.
claude_agents() { claude agents --json 2>"${1:-/dev/null}"; }

# session_state <name> [listing] — the state Claude Code reports for <name>'s session (panes.py's
# session_state over one claude_agents call, its listing on stdin, or over <listing>, one a caller
# read once for many agents, empty when that read failed): busy, idle, waiting[:
# <waitingFor>], unknown or gone; `herdr` when herdr answers for the agent instead (codex, or no
# session recorded). A reader that fails, or prints nothing, is unknown, never herdr.
session_state() {
  local list ok=1 out
  if [[ $# -gt 1 ]]; then list="$2"; [[ -n "$2" ]] || ok=""; else list="$(claude_agents)" || ok=""; fi
  out="$(printf '%s' "${list}" | SWARM_LIST_OK="${ok}" SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *
s = session_state(sys.argv[1], sys.argv[2], sys.stdin.read() if os.environ["SWARM_LIST_OK"] else None)
print("herdr" if s is None else s[0] + (": " + s[1] if s[1] else ""))' "${AGENTS_LOG}" "$1")" || out=""
  echo "${out:-unknown}"
}

# read_state <name> — <name>'s state for a reader that does not wait (tell, free_agent_name):
# session_state's word for a Claude agent, or `herdr:<herdr's status>` for one herdr answers for
# (codex, or no session recorded). The one place such a reader takes herdr's status.
read_state() {
  local s
  s="$(session_state "$1")"
  [[ "${s}" != herdr ]] || s="herdr:$(agent_status "$1")"
  echo "${s}"
}

# waiting_for <state> — what a waiting agent waits for (read_state's `waiting: <waitingFor>`), or
# "a prompt" when its state does not say.
waiting_for() { local w="${1#waiting: }"; [[ "${w}" != "$1" ]] || w="a prompt"; echo "${w}"; }

# login_expired <name> — succeed when <name>'s Claude session stopped on an expired login (panes.py's
# login_expired): only the user's /login clears it, so nudging or waiting on it is wasted.
login_expired() {
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *
sys.exit(0 if login_expired(*sys.argv[1:4]) else 1)' "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}"
}

# record_agent <role> <name> <kind> <model> <effort> <session> — append the agent's line; session is
# '-' for codex.
record_agent() {
  local rc=0
  mkdir -p "$(dirname "${AGENTS_LOG}")"
  # Under the log's lock, so start_rung's drop of an unstarted rung (a read, then a replace) never
  # loses this line.
  state_lock "${AGENTS_LOG}.lock"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$1" "$2" "$3" "$4" "$5" "${6:--}" >> "${AGENTS_LOG}" || rc=$?
  rmdir "${AGENTS_LOG}.lock"
  # The version it starts on, for upgrade to print; one it cannot write reads as unknown there.
  # Read first, so a failed read never leaves an empty file in place of the last one.
  local v
  v="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json" 2>/dev/null)" || v=""
  [[ -z "${v}" ]] || { mkdir -p "${VERSIONS_DIR}" && echo "${v}" > "${VERSIONS_DIR}/$2"; } 2>/dev/null || true
  return "${rc}"
}

# VERSIONS_DIR: the plugin version the agent holding each name started on (record_agent, upgrade).
VERSIONS_DIR="${PROJECT_DIR}/.swarm/versions"

# EVENTS_LOG: an append-only audit of every command that changes state, one line each (time, command,
# target, the actor's herdr pane, outcome). Names and paths only, never a brief's or a message's contents;
# outcome alone can hold free text (a reset's or drop's reason, a dialog's answer, a failed command's error).
EVENTS_LOG="${PROJECT_DIR}/.swarm/events.tsv"

# record_event <command> <target> [outcome] — append one line. A log that cannot be written never
# fails the command it records.
record_event() { append_event "$@" || true; }

# append_event <command> <target> [outcome] — record_event's append, failing when the line was not
# written, for a command whose only output is that line (intervene).
append_event() {
  local x fields=()
  for x in "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:--}" "${HERDR_PANE_ID:--}" "${3:-ok}"; do fields+=("${x//[$'\t\n\r']/ }"); done
  { mkdir -p "${EVENTS_LOG%/*}" && printf '%s\t%s\t%s\t%s\t%s\n' "${fields[@]}" >> "${EVENTS_LOG}"; } 2>/dev/null
}

# story_text <slug> — the story file on the board or, once a merge deleted it, its last version in
# the board's git history; nothing when neither has it.
story_text() {
  local f="${BOARD}/stories/$1.md" c
  if [[ -f "${f}" ]]; then cat "${f}"; return; fi
  c="$(git -C "${BOARD}" log --diff-filter=D -1 --format=%H -- "stories/$1.md" 2>/dev/null)" || return 0
  [[ -z "${c}" ]] || git -C "${BOARD}" show "${c}^:./stories/$1.md" 2>/dev/null || true
}

# PROMPT_TIMEOUT_MS: how long a prompt has to be taken up (deliver_prompt), and a /goal to show in
# the session log (send_goal). SLOW_PROMPT_TIMEOUT_MS: how long start_agent gives a fable brief in all,
# since fable at xhigh can take over 60 s to show it is working (SWARM_PROMPT_TIMEOUT_MS overrides
# it), and how long start_rung reads a new rung again before closing it (rung_late).
PROMPT_TIMEOUT_MS="${SWARM_PROMPT_TIMEOUT_MS:-60000}"
SLOW_PROMPT_TIMEOUT_MS=300000

# deliver_prompt <name> <prompt-file> [<pane>] [once] — submit the brief and confirm the agent acted on it.
# `agent start` returns once the agent is ready, but a slow starter (Fable at xhigh) could
# still drop a prompt sent at once, leaving it idle at an empty prompt while every later
# `wait` returned immediately. So the submission waits until herdr sees the agent working
# (or blocked on a question), and fails loudly rather than reporting success. It reports the
# prompt taken on evidence: herdr's reply, or prompt_settle (working, blocked, a turn finished since,
# or, for an agent whose Claude session read idle before the send, that session busy, waiting, or
# with the prompt in its log since: DELIVER_LINE, else the file's first non-blank line). It sends it
# again only on evidence it was not taken: prompt_settle found the agent idle or done with no turn
# finished since, and, if herdr sent it, that Claude session showed no sign of it. herdr's screen can
# read idle through a whole turn (plan-hld-command's four findings tells on 2026-10-24, each sent
# twice), so a prompt herdr sent to an agent with no session to read (codex, a session Claude Code
# does not list yet, or one it reads busy, waiting or not at all) is never sent again: when no turn
# shows, it succeeds with a warning that herdr sent it the brief and did not show the turn start. A
# prompt herdr refused before sending fails at once, naming herdr's code. Anything else (no read
# before the prompt, no status) fails saying it may or may not have it.
# With once, it is sent a single time and the caller confirms it: a /goal sent again would reset
# a goal that set, and whether it set is in the session log, not in herdr's status.
deliver_prompt() {
  local name="$1" prompt_file="$2" target="${3:-}" reply verdict status before try sent=0 unread=0 sess="" mark="" line=""
  [[ -n "${target}" ]] || target="$(own_target "${name}")"
  if [[ "${4:-}" == once ]]; then
    herdr agent prompt "${target}" "$(cat "${prompt_file}")" >/dev/null 2>&1 \
      || die "${name}: herdr could not send it the prompt; see herdr agent read ${name}"
    return
  fi
  read -r status before <<< "$(agent_info "${target}")"   # the baseline, before anything goes out
  # Claude Code's own view, for an agent started with a Claude session on record (AGENTS_LOG) that
  # Claude Code reads idle: the session to read.
  if awk -F'\t' -v n="${name}" 'NF == 7 && $3 == n && $4 == "claude" { f = 1 } END { exit !f }' "${AGENTS_LOG}" 2>/dev/null \
    && [[ "$(session_state "${name}")" == idle ]] && mark="$(session_mark "${name}")"; then
    sess="${name}" line="${DELIVER_LINE:-$(awk 'NF { print; exit }' "${prompt_file}")}"
  fi
  for try in 1 2; do
    reply="$(prompt_once "${target}" "${prompt_file}")"
    case "${reply}" in
      working|blocked) return 0 ;;
      sent) sent=$((sent + 1)) ;;
      unread) unread=$((unread + 1)) ;;
      agent_blocked) [[ ${sent} -eq 0 ]] || return 0   # blocked on a question about the one herdr sent
        [[ ${unread} -eq 0 ]] || die "${name}: it may or may not have the brief: $(sent_note 0 "${unread}"), then herdr refused the next: it is blocked on a question (agent_blocked); it was not sent again, see herdr agent read ${name}"
        die "${name}: herdr did not send it the brief: it is blocked on a question (agent_blocked); answer it, see herdr agent read ${name}" ;;
      *) [[ $((sent + unread)) -gt 0 ]] || die "${name}: herdr did not send it the brief (${reply}); see herdr agent read ${name}"
         die "${name}: $(sent_note "${sent}" "${unread}"), then could not send it again (${reply}); see herdr agent read ${name}" ;;
    esac
    verdict="$(prompt_settle "${target}" "${status}" "${before}" "${sess}" "${mark}" "${line}")"
    case "${verdict}" in
      taken) return 0 ;;
      again\ *) if [[ ${sent} -gt 0 && -z "${sess}" ]]; then
          echo "warning: ${name}: $(sent_note "${sent}" "${unread}"), and herdr did not show the turn start (it reads it ${verdict#again } with no turn finished since); it was not sent again, see herdr agent read ${name}" >&2
          return 0
        fi ;;
      *) die "${name}: it may or may not have the brief: $(sent_note "${sent}" "${unread}"), then ${verdict#unsure }; it was not sent again, see herdr agent read ${name}" ;;
    esac
  done
  die "${name}: the brief was not taken up: $(sent_note "${sent}" "${unread}"), and herdr reads it ${verdict#again } with no turn finished since; see herdr agent read ${name}"
}

# count_word <n> — once or twice.
count_word() { if [[ "$1" -eq 1 ]]; then echo once; else echo twice; fi; }

# sent_note <sent> <unread> — what deliver_prompt knows went out: the prompts herdr sent, and those
# whose reply could not be read (sent or not, no one knows).
sent_note() {
  if [[ "$1" -gt 0 && "$2" -gt 0 ]]; then echo "herdr sent it the brief once, and its reply to the other try could not be read"
  elif [[ "$1" -gt 0 ]]; then echo "herdr sent it the brief $(count_word "$1")"
  elif [[ "$2" -gt 0 ]]; then echo "herdr's reply to the brief could not be read $(count_word "$2")"
  else echo "herdr sent it nothing"; fi
}

# prompt_once <target> <prompt-file> — submit the prompt once, wait for it to be taken up, and print
# what came of it: working or blocked; herdr's code when it refused before sending anything
# (agent_blocked, agent_not_found, pane_not_found, or server_unavailable: no herdr to send it); sent,
# for any other error (timeout, agent_prompt_stalled, agent_prompt_failed or a code a newer herdr adds:
# herdr may have sent it) or a reply with no status; unread, when herdr failed with no error it could
# read (it may be down: whether it sent anything is unknown).
# herdr's reply (stdout) or error (stderr) is the last JSON line of the two read together: no temp
# file for a TERM to leave behind, and a line herdr adds (warning:, server_binary_stale:) is skipped.
prompt_once() {
  local all r rc=0
  all="$(herdr agent prompt "$1" "$(cat "$2")" --wait --until working --until blocked \
    --timeout "${PROMPT_TIMEOUT_MS}" 2>&1)" || rc=$?
  r="$(last_json "${all}")"
  case "${r}" in
    working:*|blocked:*) echo "${r%%:*}" ;;
    *:agent_blocked|*:agent_not_found|*:pane_not_found|*:server_unavailable) echo "${r#*:}" ;;
    :) if [[ ${rc} -eq 0 ]]; then echo sent; else echo unread; fi ;;
    *) echo sent ;;
  esac
}

# last_json <text> — "<agent_status>:<error code>" from the last line of <text> that is a JSON object,
# either part empty when it has none.
last_json() {
  python3 -I -c 'import json, sys
r = {}
for line in sys.argv[1].splitlines():
    try:
        o = json.loads(line)
    except ValueError:
        continue
    if isinstance(o, dict):
        r = o
a, e = r.get("result") or {}, r.get("error") or {}
print("%s:%s" % ((a.get("agent") or {}).get("agent_status") or "", e.get("code") or ""))' "$1" 2>/dev/null || echo :
}

# agent_info <target> — "<status> <completion_seq>" from herdr agent get, either one - when herdr gives
# none (so read keeps them apart). herdr 0.9.5 gives completion_seq only to a done agent, equal to its
# state_change_seq when the turn completed; any other status has no such key.
agent_info() {
  local s seq
  read -r s seq <<< "$(herdr agent get "$1" 2>/dev/null | json "'%s %s' % (d['result']['agent'].get('agent_status') or '-', d['result']['agent'].get('completion_seq', '-'))" 2>/dev/null)"
  echo "${s:--} ${seq:--}"
}

# SETTLE_READS: how many times prompt_settle reads an agent, 5 s apart: for PROMPT_TIMEOUT_MS, as long
# as a prompt has to be taken up, so a slow starter still idle after herdr's 5 s is not sent it again.
SETTLE_READS=$((PROMPT_TIMEOUT_MS / 5000 > 1 ? PROMPT_TIMEOUT_MS / 5000 : 1))

# prompt_settle <target> <status-before> <completion-before> [<name> <mark> <line>] — after a prompt
# that went out (or may have) with no status in herdr's reply, read the agent (agent_info) until it
# shows it took it, and print what came of it, against agent_info's read before the prompt (a status
# of - or unknown there is no baseline). taken: working, blocked, a completion_seq that was not there
# before (a turn finished since), or, given <name>, its Claude session showing it took the prompt
# (session_took past <mark>, for <line>), so a turn herdr's screen misses, or a short one between two
# reads, counts. "again <status>": no turn ran: idle before and on the last read with no
# completion_seq, or done with the same completion_seq. Else "unsure <why>": two failed reads in a
# row (herdr down), no baseline, or anything else.
prompt_settle() {
  local s="-" c="-" i misses=0 known=yes
  case "$2" in idle|done|working|blocked) ;; *) known="" ;; esac
  for ((i = 1; i <= SETTLE_READS; i++)); do
    nap 5
    read -r s c <<< "$(agent_info "$1")"
    case "${s}" in
      working|blocked) echo taken; return ;;
      -) misses=$((misses + 1)); if [[ ${misses} -ge 2 ]]; then break; fi; continue ;;
    esac
    misses=0
    if [[ -n "${known}" && "${c}" != - && "${c}" != "$3" ]]; then echo taken; return; fi
    if [[ -n "${4:-}" ]] && session_took "$4" "$5" "$6"; then echo taken; return; fi
  done
  if [[ -n "${known}" && "${c}" == "$3" ]] && [[ ( "${s}" == idle && "$2" == idle ) || ( "${s}" == "done" && "${c}" != - ) ]]; then echo "again ${s}"
  elif [[ "${s}" == - ]]; then echo "unsure herdr gave no status for it"
  elif [[ -z "${known}" ]]; then echo "unsure herdr reads it ${s}, with nothing from before the prompt to compare it with"
  else echo "unsure herdr reads it ${s} with no turn finished since"; fi
}

# session_mark <name> — the byte size of <name>'s own Claude session log (its agents.tsv session id,
# report.py's session_log), 0 when it has none yet, for session_took to read past.
session_mark() {
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *; from report import session_log
sid = session_id(sys.argv[1], sys.argv[2]); path = session_log(sys.argv[3], sid) if sid else ""
print(os.path.getsize(path) if path else 0)' "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}"
}

# session_took <name> <mark> <line> — succeed when <name>'s Claude session shows it took a prompt:
# Claude Code reads it busy or waiting (one claude_agents call), or its main log has, past byte
# <mark>, a user prompt (panes.py's is_prompt, not a Task subagent's entry) whose text holds <line>
# (whitespace aside). Not a tool result, an automated prompt or another tell's: a turn the prompt did
# not start writes those too.
session_took() {
  { claude_agents || true; } | SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *; from report import session_log
log, name, projects, mark, line = sys.argv[1:6]
if (session_state(log, name, sys.stdin.read() or None) or ("",))[0] in ("busy", "waiting"):
    sys.exit(0)
want, sid = " ".join(line.split()), session_id(log, name)
path = session_log(projects, sid) if sid else ""
if not want or not path:
    sys.exit(1)
with open(path, "rb") as f:
    f.seek(int(mark))
    for l in f:
        try:
            d = json.loads(l)
        except ValueError:
            continue
        if not isinstance(d, dict) or d.get("type") != "user" or d.get("isSidechain") or not is_prompt(d):
            continue
        c = (d.get("message") or {}).get("content")
        if isinstance(c, list):
            c = " ".join(str(x.get("text") or "") for x in c if isinstance(x, dict) and x.get("type") == "text")
        if want in " ".join(str(c or "").split()):
            sys.exit(0)
sys.exit(1)' "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}" "$2" "$3" 2>/dev/null
}

# IDLE_NUDGES: how many times one `wait` re-prompts a builder that went idle before its story has a
# PR (its turn died on a dropped stream, or it stopped early): nothing else would wake it. Enough to ride
# out a dropped stream; few enough that a builder that is truly stuck still comes back to the lead.
IDLE_NUDGES=3

# nudge_reason <name> — when <name> builds a ready code, docs or chore story that has no open or
# merged PR (a closed one is an earlier attempt's, closed by a counted close), print why a nudge is
# sent and succeed. A name with no story (a conductor, hld, a planner) is never nudged, and a repo
# that cannot be resolved, or a gh or git call that fails, counts as having a PR.
nudge_reason() {
  local slug f src url n
  slug="$(stall_py story "$1")"; [[ -n "${slug}" ]] || return 1
  f="${BOARD}/stories/${slug}.md"
  case "$(fm "${f}" kind)" in ""|code|docs|chore) ;; *) return 1 ;; esac
  [[ "$(fm "${f}" status)" == ready ]] || return 1   # a story being built stays ready until review
  src="$(repo_dir "$(fm "${f}" repo)")" || return 1
  url="$(git -C "${src}" remote get-url origin 2>/dev/null)" || return 1
  n="$(gh pr list -R "${url}" --head "story/${slug}" --state all --json state -q '[.[] | select(.state != "CLOSED")] | length' 2>/dev/null)" || return 1
  [[ "${n}" == 0 ]] || return 1
  echo "you are idle and story/${slug} has no PR"
}

# API_RESUMES: how many API-error stops in a row one `wait` resumes before it returns `stuck: api
# error` for the lead. An API error is transient; one that keeps coming back is not.
API_RESUMES=3
API_RESUME_MSG="Your last turn stopped on an API error; carry on where you stopped."

# pane_text <target> — the recent text of the agent's pane, or nothing when herdr cannot read it.
pane_text() { herdr agent read "$1" --source recent-unwrapped 2>/dev/null || true; }

# pane_sum <target> — the checksum of pane_text, as pane_check takes it.
pane_sum() { printf '%s' "$(pane_text "$1")" | cksum; }

# PANE_DIR: per agent, a file kept by pane_check and read by dash: its pane's checksum, when status or
# wait first saw the pane so (epoch seconds), and the id of the logged stop its turn ended on (stop_id). It
# moves with the agent when it retires (retire_agent), so its renamed pane logs nothing again, and goes
# when a new agent takes its name.
PANE_DIR="${PROJECT_DIR}/.swarm/panes"

# pane_stop — read pane text on stdin and print "<line number>\t<kind>\t<prompt>\t<line>" for the stop
# its last turn ended on: no reply (⏺ or ●) and no submitted prompt (`> text`) after it. <prompt> is
# the line number of the last submitted prompt above it, 0 for none. The stop is Claude Code's own
# `API Error:` line, after ⏺ or ● at the margin (api-error), or the tool result Claude Code gives for a
# denial, `Error: Permission for this action was denied by the Claude Code auto mode classifier.`
# (auto-denied). An agent's own indented text, or a tool's output (⎿) that prints `API Error:` or
# quotes the denial, is neither. The input box at the bottom is not read: a suggestion or half-typed text
# there is no prompt. It is the last two border lines (─ at the margin) with no reply from the upper
# one down; a box higher up (a banner, a dialog) is read as any line.
pane_stop() {
  awk '{ l[NR] = $0 } /^(╭|╰)?─/ { t = b; b = NR }
    END {
      n = NR; if (!t) t = b
      if (t) { n = t - 1; for (i = t; i <= NR; i++) if (l[i] ~ /^(⏺|●)/) n = NR }
      for (i = 1; i <= n; i++) {
        if (l[i] ~ /^(⏺|●)[[:space:]]*API Error:/) { s = i; k = "api-error" }
        else if (l[i] ~ /^[[:space:]]*(⏺|●)/) s = 0
        else if (l[i] ~ /^(>|❯) +[^ ]/) { s = 0; q = i }
        else if (l[i] ~ /^[[:space:]]*⎿[[:space:]]*Error: Permission for this action was denied by the Claude Code auto mode classifier/) { s = i; k = "auto-denied" }
        if (s == i) p = q + 0
      }
      if (s) { x = l[s]; sub(/^[[:space:]]*(⎿|⏺|●)?[[:space:]]*/, "", x); print s "\t" k "\t" p "\t" x }
    }'
}

# turn_ended <name> — succeed when herdr says <name> is done or idle. Its session can still read busy
# after a stop: background shells it left open keep it so.
turn_ended() { [[ "$(agent_status "$1")" =~ ^(done|idle)$ ]]; }

# stop_id <text> <n> <prompt> <line> — a stop's id, <turn>/<line>: the checksum of <text>'s lines from
# the prompt above the stop to the stop (n), `-` with no prompt (0), and the checksum of its line.
stop_id() {
  local turn=-
  [[ "$3" -eq 0 ]] || turn="$(sed -n "$3,$2p" <<< "$1" | cksum | tr ' ' -)"
  printf '%s/%s\n' "${turn}" "$(printf '%s' "$4" | cksum | tr ' ' -)"
}

# pane_check <name> <target> [<sum>] — read <target>'s pane once, keep PANE_DIR/<name>, and set the
# caller's pane_at (when the pane last changed; with no file yet, when the wait began, or now) and
# pane_kind (the stop its turn ended on, pane_stop, once turn_ended; else empty). With <sum> (the pane's
# checksum when wait last resumed it, pane_sum), a pane still that same text is no new stop: the resume
# has not shown yet. A stop is logged as an api-error or auto-denied incident for <name> with its line
# unless the record holds it already: the record keeps the stop's id (stop_id) until a read finds no
# stop. It is the same stop when its turn is, or, with no prompt above it left in the window (the
# window scrolled), when its line is. So a stop after a new prompt (a resume) is logged even with no
# stop-free read between. The read and the write are under PANE_DIR/<name>.lock (mkdir(2), through
# perl as in state_lock), so of concurrent readers one logs and the rest only read. Only status and wait call it. An empty read sets
# both empty.
# ponytail: a lock a killed reader left is broken after a minute.
pane_check() {
  local f="${PANE_DIR}/$1" lock="${PANE_DIR}/$1.lock" text sum seen="" logged="" hit n p line now t new=""
  pane_kind="" pane_at=""
  [[ -n "$1" ]] || return 0
  mkdir -p "${PANE_DIR}" 2>/dev/null || true
  perl -e 'mkdir shift or exit 1' "${lock}" || { find "${lock}" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null; perl -e 'mkdir shift or exit 1' "${lock}"; } || lock=""
  text="$(pane_text "$2")"
  if [[ -n "${text}" ]]; then
    sum="$(printf '%s' "${text}" | cksum)"
    [[ ! -f "${f}" ]] || IFS=$'\t' read -r seen pane_at logged < "${f}" || true
    if [[ -z "${seen}" ]]; then pane_at="${SWARM_WAIT_STARTED:-$(date +%s)}"
    elif [[ "${sum}" != "${seen}" || -z "${pane_at}" ]]; then pane_at="$(date +%s)"; fi
    hit="$(pane_stop <<< "${text}")"; now="${logged}"; [[ -n "${hit}" ]] || now=""
    if [[ -n "${hit}" ]] && turn_ended "$1" && [[ -z "${3:-}" || "${sum}" != "$3" ]]; then
      IFS=$'\t' read -r n pane_kind p line <<< "${hit}"; now="$(stop_id "${text}" "${n}" "${p}" "${line}")"
      [[ -n "${logged}" && ( ( "${now%/*}" != - && "${now%/*}" == "${logged%/*}" ) || ( "${now%/*}" == - && "${now#*/}" == "${logged#*/}" ) ) ]] || new=1
    fi
    if [[ -n "${lock}" ]]; then
      { t="$(mktemp "${f}.XXXXXX")" && printf '%s\t%s\t%s\n' "${sum}" "${pane_at}" "${now}" > "${t}" && mv -f "${t}" "${f}"; } 2>/dev/null || true
      [[ -z "${new}" ]] || record_event incident "$1" "${pane_kind}: ${line}"
    fi
  fi
  [[ -z "${lock}" ]] || rmdir "${lock}" 2>/dev/null || true
}

# api_stopped <name> <target> — succeed when <name>'s turn ended (turn_ended) on an `API Error:` line
# (pane_stop). It only reads, for next and tell; wait reads through pane_check, which logs the stop.
api_stopped() { [[ "$(pane_text "$2" | pane_stop | cut -f2)" == api-error ]] && turn_ended "$1"; }

# resume_agent <name> <target> — send API_RESUME_MSG once through deliver_prompt (once: no retry,
# which would send it twice when the resumed turn errors before herdr shows it working); succeed when
# herdr took it. Its line then stands in the pane after the error, so api_stopped no longer holds
# until a new error. deliver_prompt's die ends only the subshell here.
resume_agent() {
  local f rc=0
  f="$(mktemp "${TMPDIR:-/tmp}/swarm-resume.XXXXXX")" || return 1
  printf '%s\n' "${API_RESUME_MSG}" > "${f}"
  (deliver_prompt "$1" "${f}" "$2" once) >/dev/null 2>&1 || rc=$?
  rm -f "${f}"; return "${rc}"
}

# bg_running <name> — succeed when <name>'s Claude session has a background task (a shell, an async
# subagent, a monitor) it started and has not yet been told the end of (panes.py's bg_running, over
# its transcript): it is waiting on it.
bg_running() {
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *
sys.exit(0 if bg_running(*sys.argv[1:4]) else 1)' "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}"
}

# usage_state <target> — print `dialog <option>` or `waiting` and succeed when the agent's pane is on
# Claude Code's usage limit (panes.py's usage_limit); fail otherwise.
usage_state() {
  pane_text "$1" | SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import usage_limit
u = usage_limit(sys.stdin.read())
sys.exit(1) if u is None else print(" ".join(u).strip())'
}

# usage_event <name> — log a usage-limit event for <name>, unless its newest events.tsv line is one.
# ponytail: one wait logs once per limit (its own flag); a new limit with no other event for <name>
# since the last is not logged again. A reset time in the event would tell them apart.
usage_event() {
  awk -F'\t' -v n="$1" '$3 == n { k = $2 } END { exit k == "usage-limit" ? 0 : 1 }' "${EVENTS_LOG}" 2>/dev/null \
    || record_event usage-limit "$1"
}

# is_builder <name> — succeed when <name>'s newest agents.tsv line has a building role (BUILDER_ROLES).
is_builder() {
  local r
  r="$(awk -F'\t' -v n="$1" '$3 == n { r = $2 } END { print r }' "${AGENTS_LOG}" 2>/dev/null)"
  [[ -n "${r}" && " ${BUILDER_ROLES} " == *" ${r} "* ]]
}

# pane_quiet <name> <target> — after pane_check: succeed when the caller's pane_at is stall_minutes
# old and the agent runs no background task (bg_running), setting the caller's state to `stuck: no
# output for <N>m (<target>)`. An empty read says nothing.
pane_quiet() {
  local min
  [[ -n "${pane_at}" ]] || return 1
  min=$((($(date +%s) - pane_at) / 60))
  # shellcheck disable=SC2154 # assigned in another file
  [[ ${min} -ge ${CFG_stall_minutes} ]] || return 1
  ! bg_running "$1" || return 1
  state="stuck: no output for ${min}m ($2)"
}

# STALL_PATHS: how many of a worktree's changed and untracked files story_work_time reads the mtime of.
STALL_PATHS=300

# story_work_time <slug> — the epoch time a story's worktree last showed work: the newer of its last
# commit and the newest mtime among its changed and untracked files (git status, the first
# STALL_PATHS of them), so a builder holding its diff uncommitted is not stalled; empty when it has
# neither (not started, or its repo is not here).
story_work_time() {
  local src wt ct
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo 2>/dev/null)")" || return 0
  wt="$(worktree_for "${src}" "$1")"
  ct="$(git -C "${wt}" log -1 --format=%ct 2>/dev/null || true)"
  { GIT_OPTIONAL_LOCKS=0 git -C "${wt}" status --porcelain -z --untracked-files=all 2>/dev/null || true; } \
    | python3 -c '
import os, sys
wt, cap, best = sys.argv[1], int(sys.argv[2]), [float(sys.argv[3])] if sys.argv[3] else []
es, i = sys.stdin.read().split("\0"), 0
while i < len(es) and cap > 0:
    e, i = es[i], i + 1
    if len(e) < 4:
        continue
    i += e[0] in "RC"   # a rename or copy: its source path follows
    cap -= 1
    try:
        best.append(os.lstat(os.path.join(wt, e[3:])).st_mtime)
    except OSError:   # deleted
        pass
print(int(max(best)) if best else "")' "${wt}" "${STALL_PATHS}" "${ct}" || echo "${ct}"
}

# story_rows — one "slug<TAB>agent name<TAB>status<TAB>prs" line per story, for stall.py's story_for.
story_rows() {
  local f r
  while IFS= read -r f; do
    r="$(basename "${f}" .md)"
    printf '%s\t%s\t%s\t%s\n' "${r}" "$(agent_name "${r}")" "$(fm "${f}" status)" "$(fm "${f}" prs)"
  done < <(board stories)
}

# stall_py <mode> <args...> — run stall.py: `story <name>` prints the agent's story (story_for, over
# story_rows); `age <slug> <name> <sign>...` prints stall_age, or nothing.
stall_py() {
  local rows=""
  [[ "$1" != story ]] || rows="$(story_rows)"
  SWARM_STORY_ROWS="${rows}" python3 "${SWARM_HOME}/bin/lib/stall_py.py" "${EVENTS_LOG}" "$@"
}

# session_mtime <name> — the epoch of the newest entry in <name>'s Claude session log (its agents.tsv
# session id, report.py's session_log) that is its own work: an assistant message, a tool call or a
# tool result, in the log or its Task subagents' logs (<session>/subagents/*.jsonl). A compaction,
# summary or background-task notice, which a hung session still writes, is no sign of life. Empty when
# it has none. Never close's copy (SESSIONS_DIR): an archive says nothing
# about a live agent.
session_mtime() {
  python3 "${SWARM_HOME}/bin/lib/session_mtime.py" "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}" || true
}

# longest_child <name> <target> — what a builder's foreground Bash tool call runs, from
# longest_child.py over ps, herdr's process info for pane <target> and its last own work
# (session_mtime): `longest-running: pid <PID>, <N> min: <program> (under <its parents>)`, program
# names only, or `longest-running: none named (<why>)`: a codex builder (agents.tsv), whose commands
# are not traced, no Bash tool call running a command, none started since its last own work, or a
# process list that could not be read.
longest_child() {
  local out
  if [[ "$(awk -F'\t' -v n="$1" '$3 == n { h = $4 } END { print h }' "${AGENTS_LOG}" 2>/dev/null)" == codex ]]; then
    echo "longest-running: none named (a codex builder)"; return
  fi
  out="$(python3 "${SWARM_HOME}/bin/lib/longest_child.py" "$(herdr pane process-info --pane "$2" 2>/dev/null)" "$(session_mtime "$1")")" || true
  echo "${out:-longest-running: none named (its processes could not be read)}"
}

# agent_stalled <name> <since> — when <name> is a story's builder that has shown no sign of life for
# stall_minutes (stall.py), counting <since> (epoch: when the wait began), its worktree's last commit
# or edit (story_work_time) and its newest own work across its session log and its subagents' logs
# (session_mtime) as signs, print how many
# minutes and succeed. Its PRs are asked for their updatedAt only once the rest already looks
# stalled, so gh is rarely called.
agent_stalled() {
  local slug url age ct sl prs=()
  slug="$(stall_py story "$1")"
  [[ -n "${slug}" ]] || return 1
  ct="$(story_work_time "${slug}")"; sl="$(session_mtime "$1")"
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}" "${sl}")"
  # shellcheck disable=SC2154 # assigned in another file
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  for url in $(fm "${BOARD}/stories/${slug}.md" prs | grep -o 'https://github.com/[^] ,"]*/pull/[0-9]*'); do
    prs+=("$(gh pr view "${url}" --json updatedAt -q .updatedAt 2>/dev/null || true)")
  done
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}" "${sl}" "${prs[@]+"${prs[@]}"}")"
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  echo "${age}"
}

# STALL_POLL_MS: how often `wait --stall` checks whether the agent it waits on has stalled.
STALL_POLL_MS="${SWARM_STALL_POLL_MS:-60000}"
# WAIT_STALLED: the exit code of `wait --stall` when it returns because the agent stalled.
WAIT_STALLED=3
# WAIT_STUCK: the exit code of any `wait` that returns "stuck: ..." (an API error resumes did not
# clear, or a pane quiet for stall_minutes): distinct from a stall, which a conductor closes on.
WAIT_STUCK=4

# timed_out <stderr file> — true when herdr's failed agent wait only timed out.
timed_out() { grep -q '"timeout"' "$1"; }

# herdr_events <target> <timeout-ms> — herdr_events.py on herdr's event stream at HERDR_SOCKET_PATH
# (herdr sets it in every pane): print idle, blocked, done or gone the moment the agent reaches it, or
# fail with 3 at the timeout; any other failure (2 with no socket or no stream, when herdr_events.py
# prints how much of <timeout-ms> is left) sends the caller to herdr agent wait.
herdr_events() {
  [[ -S "${HERDR_SOCKET_PATH:-}" ]] || return 2
  python3 "${SWARM_HOME}/bin/lib/herdr_events.py" "${HERDR_SOCKET_PATH}" "$1" "$2"
}

# herdr_step <target> <ms> <err> — one step of herdr_wait: herdr's event stream (herdr_events) for
# <ms>, or, when it has no stream or fails any other way, herdr agent wait for what is left of the
# step, its stderr in <err>. Prints the agent's state and succeeds; fails with 1 when the step timed
# out, and 2 when herdr failed or answered with no agent status.
herdr_step() {
  local target="$1" ms="$(($2 > 1 ? $2 : 1))" err="$3" out rc=0
  : > "${err}"
  out="$(herdr_events "${target}" "${ms}")" || rc=$?
  case "${rc}" in
    0) echo "${out}"; return 0 ;;
    3) return 1 ;;
  esac
  [[ ! "${out}" =~ ^[0-9]+$ ]] || ms="${out}"   # what herdr_events.py left of the step
  if out="$(herdr agent wait "${target}" --timeout "${ms}" 2>"${err}")"; then
    json "d['result']['agent']['agent_status']" <<< "${out}" && return 0
    return 2
  fi
  timed_out "${err}" && return 1
  return 2
}

# herdr_wait <target> <name> <timeout-ms> [<since>] — the wait for an agent with no Claude session to
# read (codex, or no session recorded), and the one place a wait takes herdr's own status: herdr_step
# in STALL_POLL_MS steps. With <since>, between steps an agent stalled since then (agent_stalled)
# ends the wait with "stalled: ...", and so does a pane quiet for stall_minutes (pane_check, then
# pane_quiet). A step that fails other than by timing out ends the stepping, and the last step, for
# what is left of <timeout-ms>, then fails as one unbroken wait does: 1, with herdr's stderr from the
# step that failed (why) and the last.
herdr_wait() {
  local target="$1" name="$2" left="$3" since="${4:-}" err min state rc end why="" pane_kind="" pane_at=""
  end=$(($(now_ms) + left))
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-wait.XXXXXX")"
  while [[ ${left} -gt ${STALL_POLL_MS} ]]; do
    rc=0; herdr_step "${target}" "${STALL_POLL_MS}" "${err}" || rc=$?
    [[ ${rc} -ne 0 ]] || { rm -f "${err}"; return 0; }
    [[ ${rc} -eq 1 ]] || { why="$(cat "${err}")"; left=$((end - $(now_ms))); break; }
    left=$((left - STALL_POLL_MS))
    if [[ -n "${since}" ]] && min="$(agent_stalled "${name}" "${since}")"; then
      rm -f "${err}"; echo "stalled: working ${min} min with no commit, edit, own work in the session log or PR update"; return
    fi
    pane_check "${name}" "${target}"
    if pane_quiet "${name}" "${target}"; then rm -f "${err}"; echo "${state}"; return; fi
  done
  rc=0; herdr_step "${target}" "${left}" "${err}" || { rc=1; [[ -z "${why}" ]] || echo "${why}" >&2; cat "${err}" >&2; }
  rm -f "${err}"; return "${rc}"
}

# SETTLED: the session states a wait returns on.
SETTLED='^(idle|waiting|gone)(:|$)'

# now_ms — the time in milliseconds (bash 3.2 has no EPOCHREALTIME). sleep_ms <ms> — sleep that
# long; nothing for zero or less.
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
sleep_ms() { [[ $1 -le 0 ]] || sleep "$(($1 / 1000)).$(printf '%03d' $(($1 % 1000)))"; }
# scaled <seconds> — <seconds> times SWARM_SLEEP_SCALE (default 1; make test sets 0.01, and swarm.sh
# checks it at startup), to the millisecond, but at least a tenth of a second, so no scaled poll (nap,
# poll_while, merge's CI reads) comes near a busy one. nap <seconds> — sleep that long.
scaled() { awk -v s="$1" -v k="${SWARM_SLEEP_SCALE:-1}" 'BEGIN { t = s * k; printf "%.3f\n", (t < 0.1 ? 0.1 : t) }'; }
nap() { sleep "$(scaled "$1")"; }
# poll_while <seconds> <command...> — run <command> while it succeeds, every second scaled, for
# <seconds> unscaled: the scale quickens the polling, never the wait, and each step is slept in full,
# so it is never shorter than at scale 1.
poll_while() {
  local step n
  step="$(scaled 1)"
  n="$(awk -v s="$1" -v t="${step}" 'BEGIN { n = int(s / t); if (n < s / t) n++; print n }')"
  shift
  while ((n-- > 0)) && "$@"; do sleep "${step}"; done
}

# settle <target> <name> <timeout-ms> [<since>] [wake] — block until the agent settles and print its
# state. A Claude agent has settled when its session says so (session_state: idle, waiting or gone);
# herdr's agent wait is only the wake-up, in STALL_POLL_MS slices, and its status is never parsed.
# The session is read before the first wake and right after each; every decision is taken on that
# read. Settled, it returns at once. A herdr wait that fails other than by timing out fails the wait.
# A busy agent whose pane is on the usage limit (usage_state) ends it with "usage-limit <usage_state>",
# before any other pane check. Each other busy read also reads the pane once (pane_check, past the
# caller's resumed_sum): a turn that stopped on an API error ends it with "api error", and a pane that
# has not changed for stall_minutes (pane_quiet) with "stuck: no output ...".
# With <since>, a busy builder stalled since then (agent_stalled) ends it with "stalled: ...". Busy or
# unknown (said once on stderr), it sleeps out the rest of the slice, the last one only to the
# deadline (now plus <timeout-ms>), where it reads once more, prints that state and fails. With
# wake (after a nudge), an idle read ends the wait only once a whole slice has passed, unless the
# session read busy (or waiting, or gone) in between: two nudges are never closer than a slice.
settle() {
  local target="$1" name="$2" since="${4:-}" wake="${5:-}" state deadline t0 end err min said="" rc=0 hold=0 lim
  local pane_kind="" pane_at=""
  state="$(session_state "${name}")"
  [[ "${state}" != herdr ]] || { herdr_wait "${target}" "${name}" "$3" "${since}"; return; }
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-wait.XXXXXX")"; deadline=$(($(now_ms) + $3))
  [[ -z "${wake}" ]] || hold=$(($(now_ms) + STALL_POLL_MS))
  while [[ ${hold} -gt 0 || ! "${state}" =~ ${SETTLED} ]]; do
    t0="$(now_ms)"; end=$((t0 + STALL_POLL_MS < deadline ? t0 + STALL_POLL_MS : deadline))
    if [[ ${end} -gt ${t0} ]]; then
      herdr agent wait "${target}" --timeout $((end - t0)) >/dev/null 2>"${err}" || timed_out "${err}" || rc=1
    fi
    state="$(session_state "${name}")"
    [[ "${state}" =~ ^(idle|unknown)$ ]] || hold=0
    if [[ "${state}" =~ ${SETTLED} ]] && [[ ${hold} -eq 0 || $(now_ms) -ge ${hold} ]]; then rc=0; break; fi
    if [[ ${rc} -ne 0 ]]; then cat "${err}" >&2; break; fi
    if [[ "${state}" == unknown && -z "${said}" ]]; then
      said=1; echo "swarm: ${name}: Claude Code gives no state for its session (unknown); waiting on" >&2
    fi
    if [[ "${state}" == busy ]] && lim="$(usage_state "${target}")"; then state="usage-limit ${lim}"; break; fi
    [[ "${state}" != busy ]] || pane_check "${name}" "${target}" "${resumed_sum:-}"
    if [[ "${state}" == busy && "${pane_kind}" == api-error ]]; then state="api error"; break; fi
    if [[ "${state}" == busy && -n "${since}" ]] && min="$(agent_stalled "${name}" "${since}")"; then
      state="stalled: working ${min} min with no commit, edit, own work in the session log or PR update"; break
    fi
    if [[ "${state}" == busy ]] && pane_quiet "${name}" "${target}"; then break; fi
    t0="$(now_ms)"
    if [[ ${t0} -ge ${deadline} ]]; then rc=1; break; fi
    sleep_ms $((end - t0))
  done
  rm -f "${err}"; echo "${state}"; return "${rc}"
}

# wait_agent <name> <timeout-ms> [--stall] — block until the agent settles (settle) and print its
# state; at the timeout, print the last one and fail. A builder whose session is idle before its
# story has a PR (nudge_reason) has not settled: tell it why, log `nudge <name>`, and wait again, up
# to IDLE_NUDGES times. An idle agent whose transcript ends on an expired login (login_expired) is
# never nudged: wait prints `auth`, with a line on stderr naming it. With goal on, no builder is
# nudged: a nudge would bury the reply and goal entry the conductor reads the cause from, so wait
# returns idle. A nudge herdr could not
# deliver is neither logged nor counted: wait stops nudging and returns the idle state. With --stall, a builder that shows no sign of life
# for stall_minutes after the wait began also ends it: it prints "stalled: ...", ending in
# `; longest-running: ...` (longest_child, which says why when it names none), logs that line as an incident
# and returns WAIT_STALLED; with escalate_ladder set it steps the build up instead (ladder_step stalled) and prints
# step-up's `stepped up: ...` and returns 0, or its `step-up failed: ...` and returns 1, each followed
# by the `longest-running: ...` line, which says the step-up closed the pane the PID was read in. Any wait returns WAIT_STUCK with "stuck: no output ..." on a busy agent's pane quiet
# for stall_minutes (settle), without a nudge. SWARM_WAIT_STARTED (epoch) overrides when
# the wait began, for tests.
# An agent whose turn stopped on an API error (settle's "api error", or idle and pane_check's) is sent
# API_RESUME_MSG and waited on again, logged as a resume (not a nudge: the API failed, the builder did not stop short), up to API_RESUMES stops in a row (a turn that
# ends otherwise resets the count); the next one, or a resume not taken up, returns "stuck: api error"
# (wait keeps the pane's checksum from each resume, resumed_sum: until the pane moves past it, the old
# error is no new stop, and an idle session still on it a slice later never took the resume up)
# and WAIT_STUCK. With goal on a builder (is_builder) is never resumed: the conductor reads the stop
# from the transcript, which must still end on the error (goal_rule's cleared-on-error), so it returns
# stuck at once. A conductor or review agent is resumed as with goal off. An expired login
# (login_expired) on a busy session's API-error stop is auth, as on an idle one, and never resumed.
# An agent whose pane is on Claude Code's usage limit (settle's "usage-limit", or idle or waiting and
# usage_state; an idle session under the waiting line is idle) is neither a stop nor a stall: on its
# dialog wait sends the option "Wait here, then continue automatically" (the user's standing choice)
# once (a send herdr failed is tried again a pass later), not again while that dialog stands, taking
# settle's read when settle ended on it, logs one usage-limit event for that limit
# (usage_event), counts no nudge or resume, and waits on, a slice at a time, never past its timeout,
# where it prints usage-limit and fails. A pane that already waits after that choice is the same,
# with nothing sent; pane_quiet never sees it, so it is never stuck however long it sits.
# A wait that ran out logs a wait-timeout incident, unless SWARM_WAIT_SLICE is set (the caller waits again);
# one that failed sooner is herdr's wait failing, and logs none. auth logs a login incident
# (login_incident).
wait_agent() {
  local name="$1" timeout="$2" stall="${3:-}" status nudges=0 resumes=0 target since="" rc wake="" reason t0 lim limited="" deadline out
  local answered="" resumed_sum="" pane_kind pane_at hung
  deadline=$(($(now_ms) + timeout))
  [[ -z "${stall}" ]] || since="${SWARM_WAIT_STARTED:-$(date +%s)}"
  target="$(own_target "${name}")" || return 1
  while :; do
    t0="$(now_ms)"; rc=0; status="$(settle "${target}" "${name}" "${timeout}" "${since}" "${wake}")" || rc=$?
    if [[ "${status}" == stalled:* ]]; then
      hung="$(longest_child "${name}" "${target}")"
      [[ -z "${hung}" ]] || status="${status}; ${hung}"
      record_event incident "${name}" "${status}"
      rc=0; out="$(ladder_step "$(stall_py story "${name}")" stalled)" || rc=$?
      # Stepped up, the next rung builds in the same worktree: the hung command is still the conductor's to stop.
      # Another step-up still running (STEP_UP_BUSY) closed no pane yet: the line is printed as it was read.
      [[ ${rc} == "${STEP_UP_BUSY}" ]] && out="stepping up: $(stall_py story "${name}"): another step-up of it is running; wait on its builder again"
      if [[ ${rc} == 0 || ${rc} == "${STEP_UP_PARTWAY}" || ${rc} == "${STEP_UP_BUSY}" ]]; then
        echo "${out}"
        if [[ ${rc} != "${STEP_UP_BUSY}" && "${hung}" == "longest-running: pid "* ]]; then echo "${hung}; read before the step-up closed its pane, so the PID may be gone: check it with ps first"
        else echo "${hung}"; fi
        [[ ${rc} != "${STEP_UP_PARTWAY}" ]] || return 1
        return 0
      fi
      echo "${status}"; return "${WAIT_STALLED}"
    fi
    if [[ "${status}" == stuck:* ]]; then echo "${status}"; return "${WAIT_STUCK}"; fi
    if [[ ${rc} -ne 0 ]]; then
      [[ -n "${SWARM_WAIT_SLICE:-}" || $(($(now_ms) - t0)) -lt ${timeout} ]] || record_event incident "${name}" "wait-timeout: ${status}"
      echo "${status}"; return "${rc}"
    fi
    lim=""   # settle's own read when it ended on the usage limit; else, idle or waiting, a read here
    if [[ "${status}" == usage-limit* ]]; then lim="${status#usage-limit }"
    elif [[ "${status}" =~ ^(idle|waiting) ]] && lim="$(usage_state "${target}")" && [[ "${lim}" == dialog* || "${status}" != idle ]]; then :
    else lim=""; fi
    if [[ -n "${lim}" ]]; then
      if [[ "${lim}" != dialog* ]]; then answered=""
      elif [[ -z "${answered}" ]]; then   # answered only once herdr took the key; a failed send is tried again
        if herdr pane send-keys "${target}" "${lim#dialog }" >/dev/null 2>&1; then answered=1
        else echo "swarm: ${name}: could not answer its usage-limit dialog; trying again" >&2; fi
      fi
      [[ -n "${limited}" ]] || { usage_event "${name}"; echo "swarm: ${name}: on the usage limit; it continues by itself once the limit resets" >&2; }
      limited=1; t0=$((deadline - $(now_ms)))
      if [[ ${t0} -le 0 ]]; then echo usage-limit; return 1; fi
      sleep_ms $((t0 < STALL_POLL_MS ? t0 : STALL_POLL_MS)); continue
    fi
    limited=""; answered=""
    if [[ "${status}" == idle || "${status}" == "api error" ]] && login_expired "${name}"; then
      echo "swarm: ${name}: its login expired (Login expired · Please run /login); only your /login clears it" >&2
      login_incident "${name}"
      echo auth; return 0
    fi
    pane_kind=""; [[ "${status}" != idle ]] || pane_check "${name}" "${target}"
    if [[ "${status}" == "api error" || "${pane_kind}" == api-error ]]; then
      # Idle on the very pane it was resumed from (settle held a slice): the resume was not taken up.
      [[ -z "${resumed_sum}" || "$(pane_sum "${target}")" != "${resumed_sum}" ]] || { echo "stuck: api error"; return "${WAIT_STUCK}"; }
      resumed_sum="$(pane_sum "${target}")"
      # shellcheck disable=SC2154 # assigned in another file
      if { [[ "${CFG_goal}" != off ]] && is_builder "${name}"; } || [[ ${resumes} -ge ${API_RESUMES} ]] || ! resume_agent "${name}" "${target}"; then
        echo "stuck: api error"; return "${WAIT_STUCK}"
      fi
      resumes=$((resumes + 1)); wake=1
      record_event resume "${name}"
      echo "swarm: ${name}: its turn stopped on an API error; told it to carry on (${resumes}/${API_RESUMES})" >&2
      continue
    fi
    resumes=0; resumed_sum=""
    # Only a Claude session is nudged: herdr's idle (a codex agent's) gives settle no session to hold on.
    [[ "${status}" == idle && ${nudges} -lt ${IDLE_NUDGES} && "$(session_state "${name}")" == idle ]] || break
    # With goal on, the conductor reads why the builder stopped from its reply and session log.
    # shellcheck disable=SC2154 # assigned in another file
    [[ "${CFG_goal}" == off ]] || break
    reason="$(nudge_reason "${name}")" || break
    if ! herdr agent prompt "${target}" "From swarm: ${reason}. Carry on from where you stopped and finish the story, or say what blocks you." \
      >/dev/null 2>&1; then
      echo "swarm: ${name}: ${reason}, but the nudge could not be delivered; returning ${status}" >&2; break
    fi
    nudges=$((nudges + 1)); wake=1   # settle holds a slice, or until busy, before it takes idle again
    record_event nudge "${name}"
    echo "swarm: ${name}: ${reason}; told it to carry on (${nudges}/${IDLE_NUDGES})" >&2
  done
  echo "${status}"
}

# login_incident <name> — log a login incident for <name>, once per expired login: not when its last
# incident in events.tsv (an api-error, auto-denied or stalled one aside) is one already and no ok tell that sends a prompt (findings, nudge, resume,
# or a bare tell from before kinds) nor a start of <name> (story, agent, conduct, review-agent) came
# after it. Targets are matched through agent_name (an), as a tell logs the raw slug; a conduct
# --backlog through conductor_name (b).
login_incident() {
  awk -F'\t' -v n="$1" -v b="$(conductor_name backlog)" '
    function an(x) { x = tolower(x); gsub(/[^a-z0-9_-]/, "-", x); if (x !~ /^[a-z]/) x = "s" x; return substr(x, 1, 32) }
    $2 == "incident" && $3 == n && $5 !~ /^(api-error|auto-denied|stalled):/ { login = $5 ~ /^login:/ }
    $5 == "ok" && ($2 ~ /^tell(:(findings|nudge|resume))?$/ || $2 == "story" || $2 == "agent") && an($3) == n { login = 0 }
    $5 == "ok" && ($2 == "conduct" || $2 == "review-agent") && ($3 == "--backlog" && $2 == "conduct" ? b : an(($2 == "conduct" ? "conduct-" : "review-") $3)) == n { login = 0 }
    END { exit login ? 0 : 1 }' "${EVENTS_LOG}" 2>/dev/null \
    || record_event incident "$1" "login: Login expired"
}

# wait_conductor <agent> <timeout-ms> [report] — a conductor is idle whenever it waits on its own
# builders, so idle is not settled: wait on until its report exists, it is waiting on a prompt or
# gone, or its login expired (wait_agent's auth). A review agent is waited on the same way, with its
# findings file as <report>: it goes idle while its codex-review runs in the background, and writes
# the file only once done.
# <timeout-ms> is the whole wait, so a conductor that stopped without a report cannot hang it.
# <timeout-ms> 0 (`wait --until-report`) has no deadline: each wait_agent slice is
# SWARM_CONDUCTOR_SLICE_MS (an hour), and a slice that ran out with the session still busy (or
# unknown, or on the usage limit) waits again. Such a return before the slice ran out is herdr's wait failing, and ends it.
wait_conductor() {
  local name="$1" report="${3:-}" forever="" status deadline=$((SECONDS + $2 / 1000)) poll rc ms t0
  [[ $2 -ne 0 ]] || forever=1
  while :; do
    ms=$(( (deadline - SECONDS) * 1000 > 1000 ? (deadline - SECONDS) * 1000 : 1000 ))
    [[ -z "${forever}" ]] || ms="${SWARM_CONDUCTOR_SLICE_MS:-3600000}"
    t0="$(now_ms)"; rc=0; status="$(SWARM_WAIT_SLICE="${forever}" wait_agent "${name}" "${ms}")" || rc=$?
    [[ -z "${forever}" || ${rc} -ne 1 || ! "${status}" =~ ^(busy|unknown|usage-limit)$ || $(($(now_ms) - t0)) -lt ${ms} ]] || continue
    [[ "${status}" =~ ^(idle|done)$ && ! -f "${report:-$(conductor_report "${name}")}" ]] || break
    [[ -n "${forever}" || ${SECONDS} -lt ${deadline} ]] || break
    poll="${SWARM_CONDUCTOR_POLL:-30}"; [[ -n "${forever}" ]] || (( poll <= deadline - SECONDS )) || poll=$((deadline - SECONDS))
    sleep "${poll}"
  done
  echo "${status}"
  return "${rc}"
}

# is_tell_kind <word> — true for a kind tell takes: findings, nudge, resume or note.
is_tell_kind() { case "$1" in findings|nudge|resume|note) return 0 ;; esac; return 1; }

# NOTE_WAKE_SECS: the least time between two wake prompts to one conductor (note_wake), so a burst of
# notes wakes it once.
NOTE_WAKE_SECS="${SWARM_NOTE_WAKE_SECS:-60}"

# note_wake <name> <base> <pane> — after a note to the conductor <name> (its inbox <base>.md): wake it
# now (note_wake_now), and keep one later check pending (note_wake_later), so a note held back by the
# minute, or a wake that was dropped or answered without reading, is not left for a wait to find. A
# lock held past note_lock's wait means another note is at it: that one keeps the check.
note_wake() { local rc=0; note_wake_now "$@" || rc=$?; [[ ${rc} -eq 2 ]] || note_wake_later "$1" "$2"; }

# note_wake_now <name> <base> <pane> — prompt the conductor <name> to process <base>.md now, as its
# brief says, when the inbox is there, no wake went out in the last NOTE_WAKE_SECS (<base>.woke holds the
# last one's time, set under note_lock, so of two notes at once one wins) and its turn has ended
# (upgrade_state's idle: idle, or busy only with background jobs, whose waits can run long before one
# returns). Sent once, not confirmed, so tell returns at once. None goes to one mid-turn (it reads the
# inbox when its wait returns), one that wrote its report (nobody reads its inbox), or one paused for
# upgrade's handover (<base>.upgrade, under an hour old). A lock it cannot take (exit 2), or a prompt that
# fails, is warned of, and the failed one's stamp is taken back: the note is in the inbox either way.
note_wake_now() {
  local t f rc=0 arg
  [[ -f "$2.md" && ! -f "$(conductor_report "$1")" && -z "$(find "$2.upgrade" -mmin -60 2>/dev/null)" ]] || return 0
  note_wake_due "$2" || return 0
  [[ "$(upgrade_state "$1" "$3")" == idle ]] || return 0
  note_lock "$2" || { echo "warning: ${1} was not prompted to read its inbox (${2}.lock is held); it reads it after its wait" >&2; return 2; }
  t="$(date +%s)"
  { note_wake_due "$2" && echo "${t}" > "$2.woke"; } 2>/dev/null || rc=1
  rmdir "$2.lock"
  [[ ${rc} -eq 0 ]] || return 0
  arg="$(conduct_epic "$1")"; [[ "${arg}" != backlog ]] || arg=--backlog
  if f="$(mktemp "${TMPDIR:-/tmp}/swarm-wake.XXXXXX")"; then
    printf 'From swarm: the lead left you a note in %s. Process your inbox now, as your brief says: if %s is there, read it, act on it and delete it first; then mv the inbox to %s, read that copy, act on it and delete it. Then run swarm.sh unblock --startable %s and start each story it prints as startable:, by the rule in your brief. Then end your turn, leaving any wait or watch you have running alone; start one only if none runs.\n' "$2.md" "$2.reading.md" "$2.reading.md" "${arg}" > "${f}"
    (deliver_prompt "$1" "${f}" "$3" once) 2>/dev/null || rc=$?
    rm -f "${f}"
  else rc=1; fi
  [[ ${rc} -ne 0 ]] || return 0
  if note_lock "$2"; then [[ "$(cat "$2.woke" 2>/dev/null)" != "${t}" ]] || rm -f "$2.woke"; rmdir "$2.lock"; fi
  echo "warning: ${1} was not prompted to read its inbox; it reads it after its wait" >&2
}

# note_wake_due <base> — succeed when no wake went out in the last NOTE_WAKE_SECS (<base>.woke).
note_wake_due() {
  local last
  last="$(cat "$1.woke" 2>/dev/null)" || last=0
  [[ "${last}" =~ ^[0-9]+$ ]] || last=0
  (( $(date +%s) - last >= NOTE_WAKE_SECS ))
}

# note_wake_later <name> <base> — unless one is pending already (<base>.later, which holds its start
# time and a token; one older than twice NOTE_WAKE_SECS and a minute was killed), start one check in
# the background, its output dropped: once NOTE_WAKE_SECS have passed since the last wake (or from
# now, with none due), note_wake_now on the pane that holds <name> then, so a conductor started
# meanwhile is the one woken, never the one it replaced. That wakes only if the inbox is still there
# and no wake went out meanwhile. A wake sent meanwhile, inside the minute, moves the check once to
# the end of that minute, so it is retried too. It never starts another, and removes <base>.later only
# while that still holds its own token: a new conduct may have cleared it.
note_wake_later() {
  local rc=0 tok was later="$2.later"
  tok="$(date +%s).${RANDOM}"
  note_lock "$2" || return 0
  was="$(cut -d. -f1 "${later}" 2>/dev/null)" || was=""
  [[ ! "${was}" =~ ^[0-9]+$ ]] || (( $(date +%s) - was <= 2 * NOTE_WAKE_SECS + 60 )) || rm -f "${later}"
  (set -C; echo "${tok}" > "${later}") 2>/dev/null || rc=1
  rmdir "$2.lock"
  [[ ${rc} -eq 0 ]] || return 0
  ( trap '[[ "$(cat "${later}" 2>/dev/null)" != "${tok}" ]] || rm -f "${later}"' EXIT
    sleep "$(note_wake_left "$2")"
    note_wake_due "$2" || sleep "$(note_wake_left "$2")"
    pane="$(agent_field "$1" pane_id)"
    [[ -z "${pane}" ]] || note_wake_now "$1" "$2" "${pane}" ) </dev/null >/dev/null 2>&1 &
}

# note_wake_left <base> — the seconds until NOTE_WAKE_SECS have passed since the last wake
# (<base>.woke), or NOTE_WAKE_SECS with none inside the minute.
note_wake_left() {
  local left
  left=$(( $(cat "$1.woke" 2>/dev/null || echo 0) + NOTE_WAKE_SECS - $(date +%s) ))
  (( left > 0 && left <= NOTE_WAKE_SECS )) || left="${NOTE_WAKE_SECS}"
  echo "${left}"
}

# note_lock <base> — take <base>.lock (mkdir through perl, as state_lock), clearing one a killed tell
# left over a minute ago; fails after 5 s.
note_lock() {
  local i
  for ((i = 0; i < 50; i++)); do
    perl -e 'mkdir shift or exit 1' "$1.lock" && return 0
    find "$1.lock" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null || true
    sleep 0.1
  done
  return 1
}

# tell_agent <slug> <kind> <file> — send an agent a file's contents through deliver_prompt (it
# retries, and counts a permission prompt as taken up). <kind> says why (findings, nudge or resume;
# main logs it as tell:<kind>). A header line comes first, so findings that begin with '-' are never
# read as a flag. Only an idle agent is told (read_state; a busy one whose turn stopped on an API
# error, api_stopped, counts as idle): it refuses one mid-turn (findings sent then
# would be counted as taken up at once), waiting on a prompt (the text would land in the dialog), gone,
# or of unknown state, rather than waiting on it. With goal on, findings get a fresh goal (findings_goal).
# With escalate_ladder set, a builder's STEP_UP_FINDINGS-th findings since its build started, or any
# after (findings_told), are not sent: the build is stepped up (ladder_step findings-<N>) with them in
# the handover brief, and the tell fails, saying so; a step-up that closed nothing sends them as usual.
# A note goes only to a live conductor of this project: it is appended to .swarm/inbox/<name>.md,
# which the conductor reads after each wait (conduct_brief), busy or not; one whose turn has ended
# is also prompted to read it now (note_wake).
tell_agent() {
  local kind="$2" f="$3" name msg state since inbox rc pane line
  is_tell_kind "${kind}" || die "tell: the kind must be findings, nudge or resume, not '${kind}' (or note, to a conductor) (swarm.sh tell <slug> <kind> <file>)"
  [[ -f "${f}" ]] || die "no such file '${f}'"
  name="$(agent_name "$1")"
  [[ "${kind}" != note || ( "${name}" == conduct-* && ! "${name}" =~ -done[0-9]*$ ) ]] \
    || die "${name}: a note goes only to a conductor (conduct-<epic>); tell a builder findings, nudge or resume"
  pane="$(agent_field "${name}" pane_id)"
  if [[ -z "${pane}" ]]; then
    [[ -z "$(agent_field "${name}" agent_status any)" ]] || die "${name}: the agent holding this name is not one this project started; it is never told from here"
    die "could not reach ${name}: no agent this project started holds the name; is its pane still open?"
  fi
  if [[ "${kind}" == note ]]; then
    inbox="$(conductor_inbox "${name}").md"; mkdir -p "${inbox%/*}"
    # Built first, then one append: the conductor's mv between the open and a slow write would
    # take the note into a copy it has already read.
    msg="$(printf 'From the lead (%s):\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; cat "${f}")"
    printf '%s\n\n' "${msg}" >> "${inbox}"
    queued_sent "${f}"   # a queued: line sent is one watch and next send no more
    note_wake "${name}" "${inbox%.md}" "${pane}"
    echo "noted ${name}"; return
  fi
  state="$(read_state "${name}")"
  # A turn that stopped on an API error has ended, though open background shells keep its session busy.
  [[ "${state}" != busy ]] || ! api_stopped "${name}" "${pane}" || state=idle
  case "${state}" in
    idle|herdr:idle|herdr:done) ;;
    busy|herdr:working) die "${name} is still working; run \`swarm.sh wait $1\` in the background, then tell it" ;;
    waiting*|herdr:blocked) die "${name} is waiting on $(waiting_for "${state}"); answer it (herdr agent read ${name}), then tell it" ;;
    gone) die "${name}: its Claude session has ended (gone); there is no one to tell" ;;
    unknown) die "${name}: Claude Code gives no state for its session (unknown); look at it (herdr agent read ${name}) before telling it" ;;
    herdr:unknown) die "${name}: herdr gives no state for it (unknown); look at it (herdr agent read ${name}) before telling it" ;;
    *) die "could not reach ${name} (status '${state#herdr:}'): is its pane still open?" ;;
  esac
  if [[ "${kind}" == findings ]] && (( $(findings_told "$1") >= STEP_UP_FINDINGS - 1 )); then
    rc=0; ladder_step "$1" "findings-${STEP_UP_FINDINGS}" "${f}" || rc=$?
    [[ ${rc} != 0 ]] || die "tell: ${name} was not told: these were findings round ${STEP_UP_FINDINGS} of its build, so it was stepped up, with them in its handover brief; wait on it, and do not tell it again"
    [[ ${rc} != "${STEP_UP_PARTWAY}" ]] || die "tell: ${name} was not told: its step-up failed partway, after its builder was closed; list it for the lead"
    [[ ${rc} != "${STEP_UP_BUSY}" ]] || die "tell: ${name} was not told: another step-up of it is running; wait on it, then tell it"
  fi
  msg="$(mktemp "${TMPDIR:-/tmp}/swarm-tell.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: msg is local, and deliver_prompt may exit through die
  trap "rm -f '${msg}' '${msg}.goal'" EXIT
  { echo "From the conductor:"; echo; cat "${f}"; } > "${msg}"
  # The file's own first line is what its session log is read for: every tell starts with the header.
  line="$(awk 'NF { print; exit }' "${f}")"
  if [[ "${CFG_goal}" == off || "${kind}" != findings ]]; then DELIVER_LINE="${line}" tell_deliver "${name}" "${msg}" "${kind}"; echo "told ${name}"; return; fi
  since="$(python3 -c 'import time; print(time.time())')"   # to the sub-second: an earlier tell's goal may share the second
  DELIVER_LINE="${line}" tell_deliver "${name}" "${msg}" "${kind}"
  # The findings reached the builder: if the goal step fails, log that delivery as an ok tell
  # (outcomes and the stall rule count only ok ones), beside main's line for the failure.
  # shellcheck disable=SC2064 # expand now, as above
  trap "rc=\$?; rm -f '${msg}' '${msg}.goal'; [[ \${rc} -eq 0 ]] || record_event tell:findings '$1'" EXIT
  findings_goal "$1" "${since}" "${msg}.goal"
  echo "told ${name}"
}

# tell_deliver <name> <prompt-file> <kind> — deliver_prompt, failing with its message, after any other
# stderr it printed. A findings tell herdr sent also says what to do: findings_told counts it as a
# round, so the same findings sent again as findings would count that round twice. After "may or may
# not have the brief" they are not to be sent again. After "not taken up" (read idle, no turn, twice)
# herdr may have dropped both, so the pane says whether to send them again, as a nudge: a nudge is
# not a round.
tell_deliver() {
  local err why rc
  # Not `{ ...; } || rc=$?`: on the left of || set -e is ignored inside deliver_prompt too, so an
  # own_target die in `target="$(own_target ...)"` would not stop it, and it would prompt an empty target.
  # The bare set -e after is the state tell_agent, its one caller, runs in: dispatch's set -e.
  set +e; { err="$( set -e; deliver_prompt "$1" "$2" 2>&1 1>&3 )"; } 3>&1; rc=$?; set -e
  # A success keeps its stderr too: deliver_prompt warns when herdr sent the brief and did not show the turn start.
  if [[ ${rc} -eq 0 ]]; then [[ -z "${err}" ]] || echo "${err}" >&2; return 0; fi
  if [[ "${err}" != *"swarm: "* ]]; then [[ -z "${err}" ]] || echo "${err}" >&2; exit "${rc}"; fi
  why="${err##*swarm: }"; err="${err%swarm: *}"
  [[ -z "${err}" ]] || printf '%s' "${err}" >&2
  case "$3:${why}" in
    findings:*"the brief was not taken up: herdr sent it the brief"*)
      die "${why}; the findings count as a round: read its pane (herdr agent read $1) and, if it shows they never arrived, send them again as a nudge (swarm.sh tell $1 nudge <file>), which is not a round" ;;
    findings:*"herdr sent it the brief"*) die "${why}; the findings count as delivered, a findings round of its build, so do not send them again" ;;
  esac
  die "${why}"
}

# findings_told <slug> — how many findings tells (a bare tell, from logs before kinds, too) <slug>
# has had since its build started (build_started): ok ones, and those herdr sent but deliver_prompt
# did not see taken up ("herdr sent it the brief"); not one herdr never sent. Nor one whose reply
# "could not be read" with none sent: whether it went out is unknown, so it is not counted.
findings_told() {
  awk -F'\t' -v s="$1" -v t="$(build_started "$1")" '$3 == s && $1 >= t && ($2 == "tell" || $2 == "tell:findings") && ($5 == "ok" || $5 ~ /herdr sent it the brief/) { n++ }
    END { print n + 0 }' "${EVENTS_LOG}" 2>/dev/null || echo 0
}

# free_agent_name <name> — herdr refuses a name already in use (agent_name_taken), so a second run
# reusing a name still held (a second epic's `lead`) would fail and leave an empty pane. herdr's holder decides first: with none, the name is free,
# whatever an old session says. A holder this project started is retired only when it has finished
# (read_state: idle, its session gone, or herdr's idle or done) and refused in any other state,
# naming it, so a live agent is never renamed. Names are unique across every herdr workspace, so a holder in another project is
# refused, never retired: it is that project's agent. Runs before any pane opens.
free_agent_name() {
  local state cwd
  if [[ -z "$(agent_field "$1" pane_id)" ]]; then
    [[ -z "$(agent_field "$1" agent_status any)" ]] && return 0
    cwd="$(agent_field "$1" cwd any)"   # herdr's list gives where the holder runs: name that project
    die "$1: an agent this project did not start (no tab record in .swarm/state) holds this name (herdr agent list${cwd:+; it runs in ${cwd}}); it is never retired from here. Wait for it to finish, or close its pane"
  fi
  state="$(read_state "$1")"
  case "${state}" in
    idle|gone|herdr:idle|herdr:done) ;;   # finished: the only states retired
    busy|herdr:working) die "$1: an agent with this name is still working; wait for it, or use another name" ;;
    waiting*|herdr:blocked) die "$1: an agent with this name is waiting on $(waiting_for "${state}"); answer it (herdr agent read $1), or use another name" ;;
    unknown) die "$1: Claude Code gives no state for the session holding this name (unknown); look at it (herdr agent read $1), or use another name" ;;
    herdr:unknown) die "$1: herdr gives no state for the agent holding this name (unknown); look at it (herdr agent read $1), or use another name" ;;
    *) die "$1: the agent holding this name is '${state#herdr:}', not finished, so it is not retired; look at it (herdr agent read $1), or use another name" ;;
  esac
  retire_agent "$1" >/dev/null
  [[ -z "$(agent_field "$1" pane_id)" ]] || die "$1: the name is still taken after retiring it; close its pane (herdr agent list), or use another name"
}

# agent_field <name> <field> [any] — <field> (agent_status, pane_id) of this project's agent called
# <name> (its pane is one own_panes recorded), or nothing. With "any", of whichever project's agent
# holds the name: herdr names are unique across all workspaces.
agent_field() {
  herdr agent list 2>/dev/null | SWARM_NAME="$1" SWARM_FIELD="$2" SWARM_ANY="${3:-}" SWARM_PANES="$(own_panes)" json "next((a.get(e['SWARM_FIELD']) or ('unknown' if e['SWARM_FIELD']=='agent_status' else '') for a in d['result']['agents'] if a.get('name')==e['SWARM_NAME'] and (e['SWARM_ANY'] or a.get('pane_id') in e['SWARM_PANES'].split())),'')" 2>/dev/null || true
}

# agent_status <name> — herdr's status for this project's agent called <name>, or nothing if there is none.
agent_status() { agent_field "$1" agent_status; }

# own_target <name> — the pane of this project's agent called <name>, to address herdr by: a name
# alone could reach another project's agent, since herdr names span workspaces.
own_target() {
  local pane
  pane="$(agent_field "$1" pane_id)"
  [[ -n "${pane}" ]] || die "$1: no agent this project started holds this name now: it has exited or its pane was closed, or another project holds the name, which is never addressed"
  echo "${pane}"
}

# retire_agent <name> — leave <name>'s pane open, but free its name for the next agent (a story
# retried, a new conductor for the epic): herdr renames the agent <name>-done, and the pane keeps
# its slot in the tab's state under that name, so no later agent is split into it.
retire_agent() {
  local name state new i pane
  name="$(agent_name "$1")"
  # A name reused more than once already has a <name>-done; take the first free suffix (free in any
  # project: names are unique across workspaces).
  new="${name:0:27}-done"
  for i in 2 3 4 5 6 7 8 9; do
    [[ -z "$(agent_field "${new}" agent_status any)" ]] && break
    new="${name:0:26}-done${i}"
  done
  # By pane, and only this project's: renaming by name would rename another project's agent.
  pane="$(agent_field "${name}" pane_id)"
  if [[ -z "${pane}" ]]; then echo "no agent this project started is called $1; nothing to retire"; return 0; fi
  herdr agent rename "${pane}" "${new}" >/dev/null 2>&1 \
    || die "$1: herdr could not rename it to ${new}, so its name is not free; close its pane (herdr agent list)"
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    # That pane's tab record only: STATE_DIR also holds codex briefs, whose prose must not change.
    awk -v p="${pane}" -v n="${new}" 'NF == 2 && $1 == p { $2 = n } { print }' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
  done
  # Its pane record (pane_check) goes with it, its logged stop with it.
  mv -f "${PANE_DIR}/${name}" "${PANE_DIR}/${new}" 2>/dev/null || true
  echo "retired $1 as ${new}"
}

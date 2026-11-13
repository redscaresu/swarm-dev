# shellcheck shell=bash
# test_helpers.sh — the prelude every tests/*_test.sh sources first, right after set -euo pipefail:
#
#   # shellcheck source=tests/test_helpers.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
#
# A test run on its own from a herdr pane (bash tests/<file>) inherits the pane's environment, which
# names the lead's real project: SWARM_PROJECT, which swarm.sh takes before the directory a test cd's
# into, the other SWARM_* settings, and HERDR_SOCKET_PATH, the real herdr. events_test.sh once logged
# its fixtures into the real .swarm/findings.tsv and events.tsv that way. So this drops every SWARM_*
# but the two make test sets (SWARM_SLEEP_SCALE, defaulted here as there, and SWARM_NO_CI_REFRESH) and
# HERDR_SOCKET_PATH, and HERDR_WORKSPACE_ID, the pane's own workspace, which next_pane compares a tab
# record's panes with (CI has none; a test that needs one sets it). It does not change directory: a test names its files from BASH_SOURCE, which a
# direct run gives as a relative path. Each project a test makes is pinned by a cd into it, or by
# SWARM_PROJECT on the call; make test runs every file from its TMPDIR, outside any git repo, where a
# call left unpinned stops at "not in a swarm project", so no green test has one. And it names the
# checkout these tests run from (the main checkout, from a worktree) in SWARM_FORBID_PROJECT, which
# swarm.sh refuses to act on, named directly or through a worktree of it: such a swarm.sh call stops
# before it writes. The hooks' own event lines (hooks/merge-guard.sh record, hooks/lead-stop.sh log)
# are not swarm.sh calls; each hook checks it itself and writes no line there. tests/live_logs_test.sh checks that every test sources
# this first. It also defines signer_stubs and isolate_signer, below, for a test of what signs a commit,
# no_version, for a test that compares whole events.tsv lines, and in_new_group, group_record,
# stop_group and stop_groups, for a test that stops a background process and every process it started.
for v in $(compgen -e); do case ${v} in SWARM_SLEEP_SCALE|SWARM_NO_CI_REFRESH) ;; SWARM_*) unset "${v}" ;; esac; done
unset HERDR_SOCKET_PATH HERDR_WORKSPACE_ID
export SWARM_SLEEP_SCALE="${SWARM_SLEEP_SCALE:-0.01}"
_th_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if _th_common="$(git -C "${_th_repo}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  export SWARM_FORBID_PROJECT; SWARM_FORBID_PROJECT="$(dirname "${_th_common}")"
else export SWARM_FORBID_PROJECT="${_th_repo}"; fi
unset _th_repo _th_common

# signer_stubs <dir> — stub gpg, gpg-connect-agent, ssh-add and ssh-keygen in <dir>/bin. Each appends its
# arguments, one line a call, to <dir>/log/<name>, then sleeps <dir>/stub/<name>.sleep seconds, prints
# <dir>/stub/<name>.out and exits with <dir>/stub/<name>.rc, each only when that file is there.
signer_stubs() {
  local n
  mkdir -p "$1/bin" "$1/log" "$1/stub" || return 1
  for n in gpg gpg-connect-agent ssh-add ssh-keygen; do
    printf '#!/bin/sh\nS="%s/stub/%s" L="%s/log/%s"\n' "$1" "${n}" "$1" "${n}" > "$1/bin/${n}"
    cat >> "$1/bin/${n}" <<'STUB'
printf '%s\n' "$*" >> "$L"
[ ! -f "$S.sleep" ] || sleep "$(cat "$S.sleep")"
[ ! -f "$S.out" ] || cat "$S.out"
exit "$(cat "$S.rc" 2>/dev/null || echo 0)"
STUB
    chmod +x "$1/bin/${n}"
  done
}
# isolate_signer <dir> — for a test of what signs a commit, from here on in this shell: HOME is <dir>/home,
# git reads no config but <dir>/home/.gitconfig (GIT_CONFIG_GLOBAL, GIT_CONFIG_NOSYSTEM=1, no
# GIT_CONFIG_COUNT or GIT_CONFIG_PARAMETERS) and a repository's own, GNUPGHOME and SSH_AUTH_SOCK name
# nothing real, and signer_stubs' <dir>/bin is first on PATH. No call reaches the user's real signer.
isolate_signer() {
  signer_stubs "$1" && mkdir -p "$1/home" && : > "$1/home/.gitconfig" || return 1
  export HOME="$1/home" GIT_CONFIG_GLOBAL="$1/home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 GNUPGHOME="$1/home/.gnupg" \
    SSH_AUTH_SOCK="$1/no-agent.sock" PATH="$1/bin:${PATH}"
  unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
}

# no_version — events.tsv lines (or column 5s) on stdin, each with the version= field that append_event
# ends every tail with cut, and the tail's " ~~ " too when version= was its only field. Also cuts a
# fields() line ("k=v ...", keys sorted, so version= is last, or "outcome|k=v ...") down the same way. For a test that compares
# whole lines and is not about version=; tests/events_test.sh checks version= itself.
no_version() { sed -E 's/ ~~ version=[^[:space:]]+$//; s/ version=[^[:space:]]+$//; s/(^|[|])version=[^[:space:]]+$/\1/'; }

# A background process a test starts (a swarm.sh watch, say) can leave descendants behind once it is
# stopped: a child it ran inside $( ), whose parent a kill ends, is re-parented to init, where a
# pgrep -P walk from the stopped pid never finds it, and it goes on writing under the test's root (its
# rm -rf then fails "Directory not empty", or a later check reads its write). So such a test starts the
# process as a group of its own and stops the whole group:
#
#   (cd "${p}" && in_new_group env ... bash "${SWARM}" watch > "${ROOT}/out" 2>&1) &
#   pid=$!; group_record "${pid}" "${ROOT}/groups"
#   ...
#   stop_group "${pid}" "${ROOT}/groups"
#
# and its EXIT trap runs stop_groups "${ROOT}/groups" before its rm -rf, for a group a check left
# running (the record is a file, as a group started inside $( ) sets no variable the trap can read).

# in_new_group <command> [args...] — exec <command> as the leader of a new process group, so its pid is
# the group's id, and every process it starts is in that group unless one makes its own. Run it as the
# last command of a `( ... ) &` subshell; $! is then the group. It goes through perl's setpgrp, as
# bin/lib/merge.sh's within does, which leaves every signal as it found it: an exec from python3 would
# leave SIGPIPE ignored in <command> and every process it starts, as no real watch runs
# (tests/watch_opened_test.sh checks a writer into a closed pipe ends the same with it and without).
in_new_group() { exec perl -e 'setpgrp(0, 0) or exit 126; exec { $ARGV[0] } @ARGV or exit 127' -- "$@"; }

# group_record <pid> <record> — add <pid> to <record>, one group a line, then wait until <pid> leads a
# group of its own (in_new_group has run) or has exited. The line goes in first, so a test stopped while
# this waits still has it for its EXIT trap (stop_group copes with a pid that leads no group yet).
# Returns 1, saying so on stderr, if neither happens within 5 s.
group_record() {
  local tries=50 pause=0.1 i pgid
  echo "$1" >> "$2"
  for ((i = 0; i < tries; i++)); do
    pgid="$(ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "${pgid}" && "${pgid}" != "$1" ]] || break
    sleep "${pause}"
  done
  [[ "${pgid}" != "$1" && -n "${pgid}" ]] || return 0
  echo "group_record: pid $1 still runs in group ${pgid}, not its own" >&2; return 1
}

# stop_group <pgid> [record] — stop every process in group <pgid>, and return once pgrep -g finds none.
# It STOPs the group until two reads of it agree (XNU's killpg can miss a member forked while it walks
# the group, as tests/codex_test.sh's group KILL case says), KILLs it, reaps the leader when it is this
# shell's child, then polls pgrep -g, KILLing again, for up to 5 s. A <pgid> that leads no group (the
# process never ran in_new_group, which group_record said) is KILLed alone, so the wait on it cannot
# hang. Once the group is gone it drops the group's line from [record]. Returns 1, naming what is left
# on stderr, if the group outlives the poll, and 2 for a <pgid> that is not a whole number above 1
# (pgrep -g 0 is pgrep's own group).
stop_group() {
  local g="$1" record="${2-}" tries=50 pause=0.1 settle=10 i now was="" left
  [[ "${g}" =~ ^[0-9]+$ && "${g}" -gt 1 ]] || { echo "stop_group: no group id: '${g}'" >&2; return 2; }
  for ((i = 0; i < settle; i++)); do
    kill -STOP -- "-${g}" 2>/dev/null || true
    now="$(pgrep -g "${g}" || true)"; [[ "${now}" != "${was}" ]] || break; was="${now}"
  done
  kill -KILL -- "-${g}" 2>/dev/null || kill -KILL "${g}" 2>/dev/null || true
  { wait "${g}"; } 2>/dev/null || true
  for ((i = 0; i < tries; i++)); do
    left="$(pgrep -g "${g}" || true)"
    if [[ -z "${left}" ]]; then
      [[ -z "${record}" || ! -f "${record}" ]] || { grep -vx "${g}" "${record}" > "${record}.new" || true; mv "${record}.new" "${record}"; }
      return 0
    fi
    kill -KILL -- "-${g}" 2>/dev/null || true
    sleep "${pause}"
  done
  echo "stop_group: group ${g} still has $(echo "${left}" | tr '\n' ' ')after ${tries} polls" >&2
  return 1
}

# stop_groups <record> — stop_group each group <record> lists, for an EXIT trap before its rm -rf. A
# missing <record> is no group.
stop_groups() {
  local g
  [[ -f "$1" ]] || return 0
  while read -r g; do stop_group "${g}" "$1" || true; done < <(cat "$1")
}

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
# and no_version, for a test that compares whole events.tsv lines.
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

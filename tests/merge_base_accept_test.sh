#!/usr/bin/env bash
# merge_base_accept_test.sh — swarm.sh merge --head <reviewed> on a PR whose head is past the reviewed
# one. It merges a head that adds only git's own clean merges of the base (base_merges_only), printing
# an accepted: line, and refuses any other head for a new review at its head check, before
# dropped_hold runs: a merge that resolved a conflict, dropped a base line or set a submodule pointer
# by hand, a commit of the PR's own, a merge of a branch off the base, and a head that lost the
# reviewed commit. Neither way leaves
# a fetched ref. On merge_fixture.sh, with a real origin: o/r's clone ${ROOT}/r beside the project
# (repos_dir is the project's parent), whose origin is the bare ${ROOT}/o/r.git, where W, a work
# repo, pushes main and each case's refs/pull/7/head.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# No user or system git config, for W and for swarm.sh alike: no signing, and git's own merge settings.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

OR="${ROOT}/o/r.git"; W="${ROOT}/w"
wg() { git -c user.name=t -c user.email=t@t "$@"; }
# wput <file> <line>... — W's <file> holds the lines, committed on the branch checked out; prints the commit.
wput() { printf '%s\n' "${@:2}" > "${W}/$1"; wg -C "${W}" add -A; wg -C "${W}" commit -qm "$1"; wg -C "${W}" rev-parse HEAD; }
# branch <name> [<start>] — check out a new branch <name> at <start>, main by default.
branch() { wg -C "${W}" checkout -q -b "$1" "${2:-main}"; }
# land <file> <line>... — a commit on main that writes <file>, pushed to o/r.
land() { wg -C "${W}" checkout -q main; wput "$@" > /dev/null; wg -C "${W}" push -q "${OR}" main; }
# take <branch> [<file> <line>...] — on <branch>, merge main: git's own merge, or with <file> then
# written as the lines (a conflict resolved by hand); prints the merge.
take() {
  wg -C "${W}" checkout -q "$1"; wg -C "${W}" merge -q --no-ff --no-commit main > /dev/null 2>&1 || true
  [[ $# -lt 2 ]] || printf '%s\n' "${@:3}" > "${W}/$2"
  wg -C "${W}" add -A; wg -C "${W}" commit -q --no-edit; wg -C "${W}" rev-parse HEAD
}
# pr_head <commit> — PR 7's head is <commit>: green, pushed to o/r's refs/pull/7/head, and gh lists W's
# main..<commit> as the PR's commits, each with its parents.
pr_head() {
  local c ps sep="" json="["
  wg -C "${W}" push -q -f "${OR}" "$1:refs/pull/7/head"
  echo "$1" > "${FX}/head"; checks "${FX}/$1.checks" "$(run test completed success)"; statuses "${FX}/$1.status"
  for c in $(wg -C "${W}" rev-list --reverse "main..$1"); do
    ps="$(wg -C "${W}" rev-list --parents -n 1 "${c}" | cut -d' ' -f2- | sed -E 's/([0-9a-f]+)/{"sha":"\1"}/g; s/ /,/g')"
    json+="${sep}{\"sha\":\"${c}\",\"parents\":[${ps}]}"; sep=,
  done
  echo "${json}]" > "${FX}/prcommits"
}
# no_refs <name> — the run left no ref of its fetch in the clone.
no_refs() { is "$1: no refs/swarm/dropped-lines ref left" "" "$(git -C "${ROOT}/r" for-each-ref refs/swarm/dropped-lines)"; }
# accepted <name> <reviewed> <head> <merge>... — merge --head <reviewed> merged <head>, pinned, and said
# which merges it took.
accepted() {
  local name="$1" rev="$2" new="$3" m7=""; shift 3
  for c in "$@"; do m7+="${m7:+ }${c:0:7}"; done
  is "${name}: exits 0" 0 "${rc}"
  check "${name}: gh pr merge pinned to the new head" grep -q -- "^pr merge 7 .*--match-head-commit ${new}" "${ROOT}/gh.log"
  check "${name}: names the merges it took and the reviewed head" said \
    "accepted: ${URL}'s head ${new:0:7} adds only clean merges of main (${m7}) to ${rev:0:7}, the reviewed head; merging ${new:0:7}"
  no_refs "${name}"
}
# head_refused <name> <reviewed> <head> <why> — refused for a new review at the head check, not held.
head_refused() {
  refused "$1" "merge: the head of ${URL} is ${3:0:7}, not ${2:0:7}, and $4: review the new head"
  check "$1: not held" bash -c "! grep -q 'held:' '${ROOT}/out'"
  no_refs "$1"
}

wg init -q -b main "${W}"; mkdir -p "${ROOT}/o"; wg init -q --bare "${OR}"
wput f one two three four five > /dev/null; wput g g0 > /dev/null
wg -C "${W}" push -q "${OR}" main; wg clone -q "${OR}" "${ROOT}/r"

# The reviewed head plus one clean merge of main, then plus a second.
branch a; REV_A="$(wput a.txt a1)"; land g g1; A1="$(take a)"
fresh; pr_head "${A1}"; merge --head "${REV_A}" "${URL}"
accepted "one clean merge of the base" "${REV_A}" "${A1}" "${A1}"
land g g2; A2="$(take a)"
fresh; pr_head "${A2}"; merge --head "${REV_A}" "${URL}"
accepted "two clean merges of the base in a row" "${REV_A}" "${A2}" "${A1}" "${A2}"

# d and c replace f's three with three-pr; main then replaces it with three-main and main-added. d's
# merge drops main-added; c's keeps every line. Both resolved a conflict, so neither is git's own merge.
branch d; REV_D="$(wput f one two three-pr four five)"
branch c main; REV_C="$(wput f one two three-pr four five)"
land f one two three-main main-added four five
D="$(take d f one two three-pr three-main four five)"
C="$(take c f one two three-pr three-main main-added four five)"
NOT_OWN="is not git's own merge of its parents: its remerge-diff is not empty (a resolved conflict, a dropped line or an edit)"
fresh; pr_head "${D}"; merge --head "${REV_D}" "${URL}"
head_refused "a merge that drops a base line" "${REV_D}" "${D}" "merge ${D:0:7} ${NOT_OWN}"
fresh; pr_head "${C}"; merge --head "${REV_C}" "${URL}"
head_refused "a merge that resolved a conflict, keeping every line" "${REV_C}" "${C}" "merge ${C:0:7} ${NOT_OWN}"

# A commit of the PR's own after the reviewed head; and one before a clean merge of main.
branch n; REV_N="$(wput n.txt n1)"; N2="$(wput n.txt n2)"
fresh; pr_head "${N2}"; merge --head "${REV_N}" "${URL}"
head_refused "a commit after the reviewed head" "${REV_N}" "${N2}" "${N2:0:7}, after ${REV_N:0:7}, is a commit of its own, not a merge of main"
branch y; REV_Y="$(wput y.txt y1)"; Y2="$(wput y.txt y2)"; land g g3; Y="$(take y)"
fresh; pr_head "${Y}"; merge --head "${REV_Y}" "${URL}"
head_refused "a code commit, then a clean merge of the base" "${REV_Y}" "${Y}" "${Y2:0:7}, after ${REV_Y:0:7}, is a commit of its own, not a merge of main"

# The reviewed commit gone: a clean merge of main into the commit before it. The clone has the reviewed
# commit, as an earlier fetch of the PR would have left it, so git reads it as not an ancestor.
branch x; X1="$(wput x.txt x1)"; REV_X="$(wput x.txt x2)"; land g g4; branch xr "${X1}"; XR="$(take xr)"
wg -C "${W}" push -q "${OR}" "${REV_X}:refs/heads/x"; git -C "${ROOT}/r" fetch -q origin x
fresh; pr_head "${XR}"; merge --head "${REV_X}" "${URL}"
head_refused "a clean merge of the base into the reviewed head's parent" "${REV_X}" "${XR}" "${REV_X:0:7} is not in its history"
# The reviewed commit in the head's history only through main: main merged it, and the head is a clean
# merge of main into the commit before it.
branch q; REV_Q="$(wput q.txt q1)"; wg -C "${W}" checkout -q main; wg -C "${W}" merge -q --no-ff --no-edit q
wg -C "${W}" push -q "${OR}" main; branch qr "${REV_Q}~1"; QR="$(take qr)"
fresh; pr_head "${QR}"; merge --head "${REV_Q}" "${URL}"
head_refused "the reviewed head reached only through a merge's second parent" "${REV_Q}" "${QR}" "${REV_Q:0:7} is not on its first-parent chain"

# A clean merge of a branch that is not on the base.
branch side; SIDE="$(wput side.txt s1)"; branch s main; REV_S="$(wput s.txt s1)"
wg -C "${W}" merge -q --no-ff --no-edit side; SM="$(wg -C "${W}" rev-parse HEAD)"
fresh; pr_head "${SM}"; merge --head "${REV_S}" "${URL}"
head_refused "a clean merge of a branch off the base" "${REV_S}" "${SM}" "merge ${SM:0:7}'s second parent ${SIDE:0:7} is not on main"

# A merge of main that also sets a submodule pointer by hand, with diff.ignoreSubmodules=all in the
# clone, which would hide that pointer from the remerge-diff were it not overridden.
branch gl; REV_G="$(wput gl.txt g1)"; land g g5
wg -C "${W}" checkout -q gl; wg -C "${W}" merge -q --no-ff --no-commit main > /dev/null 2>&1 || true
wg -C "${W}" update-index --add --cacheinfo "160000,${REV_G},sub"; wg -C "${W}" commit -q --no-edit; GL="$(wg -C "${W}" rev-parse HEAD)"
git -C "${ROOT}/r" config diff.ignoreSubmodules all
fresh; pr_head "${GL}"; merge --head "${REV_G}" "${URL}"
git -C "${ROOT}/r" config --unset diff.ignoreSubmodules
head_refused "a merge that also sets a submodule pointer, diff.ignoreSubmodules=all in the clone" "${REV_G}" "${GL}" "merge ${GL:0:7} ${NOT_OWN}"

# git below 2.36, which has no git show --remerge-diff: refused as before.
mkdir -p "${ROOT}/oldgit"
# shellcheck disable=SC2016 # the stub's own arguments
printf '#!/bin/sh\ncase "$1" in version|--version) echo "git version 2.35.0" ;; *) exec "%s" "$@" ;; esac\n' "$(command -v git)" > "${ROOT}/oldgit/git"
chmod +x "${ROOT}/oldgit/git"
fresh; pr_head "${A1}"; merge PATH="${ROOT}/oldgit:${ROOT}/bin:${PATH}" --head "${REV_A}" "${URL}"
head_refused "git 2.35" "${REV_A}" "${A1}" "git 2.35.0 is below 2.36, the first with git show --remerge-diff, which reads its merges"

finish merge-base-accept

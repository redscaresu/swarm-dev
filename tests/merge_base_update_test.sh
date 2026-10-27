#!/usr/bin/env bash
# merge_base_update_test.sh — when the base gained code after a story PR's head went green, swarm.sh
# merge asks GitHub to merge the base into the PR's branch (update-branch, pinned to the head it
# read), reads the PR's head until it moves, and accepts the new head only when GitHub made it, its
# parents are the old head, then a commit on the base, and it changes only what that commit brings. It
# logs base-merged <new head> and stops with a base merged: line, merging nothing. Any other head, a
# conflict, another failed request, a request with no answer and a head that never moves refuse, naming
# the cause; a 422 once the head has moved checks that head. On merge_fixture.sh, whose stub serves
# update-branch (${FX}/update), the PR's head after it (${FX}/update-head), the new head's commit
# (commit.<sha>) and each compare of two commits (compare.<from>...<to>).
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

H3=3333333333333333333333333333333333333333   # the PR's head once GitHub merged main in
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb    # main's head
B0=cccccccccccccccccccccccccccccccccccccccc   # a commit behind it

# X — main's change to bin/x.sh, as a compare lists it.
X='{"filename":"bin/x.sh","status":"modified","sha":"b1","patch":"@@ -1 +1 @@\n-a\n+b"}'
# changes <to> <file>... — compare ${H1}...<to> lists <file>s, compare entries.
changes() { local to="$1" IFS=,; shift; echo "{\"files\":[$*]}" > "${FX}/compare.${H1}...${to}"; }
# PRX — the PR's own change, to bin/pr.sh (P is merge_fixture.sh's project). pr_changes <since> <file>... —
# compare <since>...${H1} lists <file>s.
PRX='{"filename":"bin/pr.sh","status":"modified","sha":"p1","patch":"@@ -1 +1 @@\n-c\n+d"}'
pr_changes() { local since="$1" IFS=,; shift; echo "{\"files\":[$*]}" > "${FX}/compare.${since}...${H1}"; }
# moved — fresh, and main gained bin/x.sh after ${H1}'s CI ran; update-branch answers, the PR's head
# becomes ${H3}, a merge of ${H1} and ${B} that changes what ${B} brings (X), and main is at ${B}.
moved() {
  fresh
  echo '{"ahead_by":1,"files":[{"filename":"bin/x.sh","status":"modified"}]}' > "${FX}/behind"
  echo '{"message":"Updating pull request branch."}' > "${FX}/update"; echo "${H3}" > "${FX}/update-head"
  parents "${H1}" "${B}"; printf '{"commit":{"sha":"%s"}}\n' "${B}" > "${FX}/basehead"
  changes "${H3}" "${X}"; changes "${B}" "${X}"; pr_changes "${B}" "${PRX}"
}
# parents <sha>... — ${H3}'s parents, as gh reads the commit, which GitHub made (committer web-flow,
# signature verified) unless ${COMMITTER} names another committer or ${VERIFIED} is false.
parents() {
  local p l=""
  for p in "$@"; do l+="${l:+,}{\"sha\":\"${p}\"}"; done
  printf '{"committer":{"login":"%s"},"commit":{"verification":{"verified":%s}},"parents":[%s]}\n' \
    "${COMMITTER:-web-flow}" "${VERIFIED:-true}" "${l}" > "${FX}/commit.${H3}"
}
PUT="api -X PUT -f expected_head_sha=${H1} repos/o/r/pulls/7/update-branch"
updated() { grep -qxF "${PUT}" "${ROOT}/gh.log"; }
# views_after_put — the pr views after the update-branch request: merge's reads of the PR's head.
views_after_put() { awk -v put="${PUT}" '$0 == put { on = 1; next } on && /^pr view/ { n++ } END { print n + 0 }' "${ROOT}/gh.log"; }
no_base_merged() { ! logged "^merge s base-merged"; }
is_zero_views() { [[ "$(views_after_put)" == 0 ]]; }
MERGED_LINE="base merged: ${URL} is now 3333333 (1111111 with main merged in); wait-pr ${URL}, then merge --head ${H3} ${URL}"

# --- main merged in, the new head's parents the old head and main's head: base merged, no merge.
moved; merge "${URL}"
refused "the base merged in" "${MERGED_LINE}"
check "the base merged in: update-branch pinned to the head merge read" updated
check "the base merged in: logs base-merged with the new head" logged "^merge s base-merged ${H3}$"
check "the base merged in: the story stays in review" grep -qx "status: review" "${S}"
# GitHub moves the head a moment after it answers: merge reads it until it does.
moved; echo 3 > "${FX}/update-lag"; merge "${URL}"
refused "a head that moves on the fourth read" "${MERGED_LINE}"
is "a head that moves on the fourth read: read four times" 4 "$(views_after_put)"
# The second parent behind main's head is still a commit on main.
moved; parents "${H1}" "${B0}"; echo '{"status":"ahead","behind_by":0}' > "${FX}/compare.${B0}"; changes "${B0}" "${X}"; pr_changes "${B0}" "${PRX}"; merge "${URL}"
refused "a second parent behind main's head" "${MERGED_LINE}"
check "a second parent behind main's head: compares it with main's head" grep -qxF "api repos/o/r/compare/${B0}...${B}" "${ROOT}/gh.log"
# The update goes to the PR's own repo.
OTHER=https://github.com/o/other/pull/7
moved; item s "status: review" "prs: ${OTHER}"; merge "${OTHER}"
refused "a PR in another repo" "base merged: ${OTHER} is now 3333333 (1111111 with main merged in)"
check "a PR in another repo: update-branch in that repo" grep -qxF "api -X PUT -f expected_head_sha=${H1} repos/o/other/pulls/7/update-branch" "${ROOT}/gh.log"

# --- The new head is not the old head with main merged in: review it.
UNCHECKED="base merge unchecked: ${URL}'s head moved from 1111111 to 3333333"
moved; parents "${H2}" "${B}"; merge "${URL}"
refused "a first parent that is not the head merge read" "${UNCHECKED}, whose parents (2222222 bbbbbbb) are not 1111111 then a commit on main: review the new head as for any new head"
check "a first parent that is not the head merge read: no base-merged line" no_base_merged
moved; parents "${H1}"; merge "${URL}"
refused "one parent, a push on top of the head" "${UNCHECKED}, whose parents (1111111) are not 1111111 then a commit on main"
check "one parent, a push on top of the head: no base-merged line" no_base_merged
moved; parents "${H1}" "${B}" "${B0}"; merge "${URL}"
refused "three parents" "${UNCHECKED}, whose parents (1111111 bbbbbbb ccccccc) are not 1111111 then a commit on main"
moved; parents "${H1}" "${B0}"; echo '{"status":"diverged","behind_by":1}' > "${FX}/compare.${B0}"; merge "${URL}"
refused "a second parent not on main" "${UNCHECKED}, whose second parent ccccccc is not on main (compared with main's head bbbbbbb: diverged)"
check "a second parent not on main: no base-merged line" no_base_merged
moved; rm "${FX}/commit.${H3}"; merge "${URL}"
refused "parents gh cannot read" "${UNCHECKED}, and gh cannot read its parents"
# A builder's own merge of main, pushed while GitHub's was pending: the same parents, but it may hold more.
moved; COMMITTER=builder parents "${H1}" "${B}"; merge "${URL}"
refused "the right parents, committed by a builder" "${UNCHECKED}, which GitHub did not make (committer builder, signature verified; GitHub's own merges are web-flow's, verified): review the new head as for any new head"
check "the right parents, committed by a builder: no base-merged line" no_base_merged
# A pusher can name web-flow as committer, but cannot sign as GitHub.
moved; VERIFIED=false parents "${H1}" "${B}"; merge "${URL}"
refused "the right parents, web-flow named but not GitHub's signature" "${UNCHECKED}, which GitHub did not make (committer web-flow, signature unverified;"
check "the right parents, web-flow named but not GitHub's signature: no base-merged line" no_base_merged
moved; echo "{\"parents\":[{\"sha\":\"${H1}\"},{\"sha\":\"${B}\"}]}" > "${FX}/commit.${H3}"; merge "${URL}"
refused "the right parents, no committer or signature" "${UNCHECKED}, which GitHub did not make (committer -, signature unverified;"
moved; rm "${FX}/basehead"; merge "${URL}"
refused "main's head gh cannot read" "${UNCHECKED}, and gh cannot read main's head to check its second parent bbbbbbb"
# GitHub's web editor makes a verified web-flow merge of these parents too, with a conflict resolved by
# hand: what the merge changes must be what main brings.
moved; changes "${H3}" "${X}" '{"filename":"docs/extra.md","status":"added","patch":"@@ -0,0 +1 @@\n+a hand edit"}'; merge "${URL}"
refused "a web-flow merge with a file main does not bring" "${UNCHECKED}, which cannot be shown to bring only main's bbbbbbb: docs/extra.md (a file the PR changes too, or not as bbbbbbb has it): review the new head as for any new head"
check "a web-flow merge with a file main does not bring: no base-merged line" no_base_merged
moved; changes "${H3}" '{"filename":"bin/x.sh","status":"modified","sha":"n1","patch":"@@ -1 +1,2 @@\n-a\n+b\n+a hand edit"}'; merge "${URL}"
refused "a web-flow merge with a line main does not bring" "${UNCHECKED}, which cannot be shown to bring only main's bbbbbbb: bin/x.sh ("
check "a web-flow merge with a line main does not bring: no base-merged line" no_base_merged
moved; changes "${H3}" '{"filename":"img.png","status":"modified","sha":"n1"}'; changes "${B}" '{"filename":"img.png","status":"modified","sha":"b1"}'; merge "${URL}"
refused "a web-flow merge with another blob of a file with no patch" "${UNCHECKED}, which cannot be shown to bring only main's bbbbbbb: img.png ("
# A file both sides changed: its merged blob is not main's, though the added and removed lines match
# (main's change, or the same lines changed at another place). It goes to review.
moved; changes "${H3}" '{"filename":"bin/x.sh","status":"modified","sha":"n1","patch":"@@ -10,3 +10,3 @@\n the PR line\n-a\n+b\n end"}'
pr_changes "${B}" "${PRX}" '{"filename":"bin/x.sh","status":"modified","sha":"p2","patch":"@@ -10 +10 @@\n-x\n+the PR line"}'; merge "${URL}"
refused "a merge of a file both sides changed" "${UNCHECKED}, which cannot be shown to bring only main's bbbbbbb: bin/x.sh (a file the PR changes too, or not as bbbbbbb has it): review the new head as for any new head"
check "a merge of a file both sides changed: no base-merged line" no_base_merged
check "a merge of a file both sides changed: compares the merge with the head, and main with the head" \
  grep -qxF "api repos/o/r/compare/${H1}...${B}" "${ROOT}/gh.log"
# A resolution that took main's version of a file the PR changed: main's blob, and the PR's edit gone.
moved; pr_changes "${B}" "${PRX}" "${X}"; merge "${URL}"
refused "a merge that drops the PR's edit for main's version" "${UNCHECKED}, which cannot be shown to bring only main's bbbbbbb: bin/x.sh (a file the PR changes too"
check "a merge that drops the PR's edit for main's version: compares main with the head, for the PR's own changes" \
  grep -qxF "api repos/o/r/compare/${B}...${H1}" "${ROOT}/gh.log"
check "a merge that drops the PR's edit for main's version: no base-merged line" no_base_merged
moved; rm "${FX}/compare.${H1}...${H3}"; merge "${URL}"
refused "what the merge changes, gh cannot read" "${UNCHECKED}, and what it changes cannot be read (unreadable compare of 1111111 with 3333333"

# --- GitHub cannot merge main in, or the head never moves: the builder merges it in.
MOVED="the base main moved past 1111111's CI (1 commits it lacks)"
moved; rm "${FX}/update-head"; echo "merge conflict between base and head" > "${FX}/update.422"; merge "${URL}"
refused "a conflict" "${MOVED}, and GitHub cannot merge it in, a conflict (HTTP 422: merge conflict between base and head): merge origin/main in, push, and merge the new head"
check "a conflict: update-branch was asked" updated
check "a conflict: no base-merged line" no_base_merged
# A 422 once the head has moved is no conflict: that head is checked. Here another merge of this PR
# went first and its head is GitHub's merge of main, so this one says base merged too.
STALE="expected head sha didn't match current head ref."
moved; echo "${STALE}" > "${FX}/update.422"; merge "${URL}"
refused "a 422 after another merge of this PR landed GitHub's merge" "${MERGED_LINE}"
is "a 422 after another merge of this PR landed GitHub's merge: reads the head once more" 1 "$(views_after_put)"
check "a 422 after another merge of this PR landed GitHub's merge: logs base-merged" logged "^merge s base-merged ${H3}$"
# Here a builder pushed after merge read the head: a new head to review, never a base merge to redo.
moved; echo "${STALE}" > "${FX}/update.422"; COMMITTER=builder parents "${H1}"; merge "${URL}"
refused "a 422 after a builder's push" "${UNCHECKED}, which GitHub did not make (committer builder, signature verified; GitHub's own merges are web-flow's, verified): review the new head as for any new head"
check "a 422 after a builder's push: no base-merged line" no_base_merged
moved; touch "${FX}/update.fail"; merge "${URL}"
refused "a failed request" "${MOVED}, and asking GitHub to merge it in failed (HTTP 502): merge origin/main in, push, and merge the new head"
# A request GitHub never answers is cut at the wait, as base_moved's reads are.
moved; touch "${FX}/update.hang"; merge SWARM_BASE_MOVED_WAIT=2 "${URL}"
refused "a request that hangs" "${MOVED}, and GitHub did not answer the request to merge it in within 2s: pull the branch first (GitHub may yet push its merge), then merge origin/main in, push, and merge the new head"
check "a request that hangs: no read of the head after it" is_zero_views
moved; rm "${FX}/update-head"; merge "${URL}"
refused "a head that never moves" "${MOVED}; GitHub took the request to merge it in, but its head was still 1111111 after 20 reads 0 s apart: pull the branch first (GitHub may yet push its merge), then merge origin/main in, push, and merge the new head"
is "a head that never moves: read 20 times, then stops" 20 "$(views_after_put)"
check "a head that never moves: no base-merged line" no_base_merged

# --- The line's next step: the new head, green and up to date, merges with --head.
moved; merge "${URL}"
checks "${FX}/${H3}.checks" "$(run test completed success)"; statuses "${FX}/${H3}.status"; rm "${FX}/behind"
merge --head "${H3}" "${URL}"
is "the base-merged head merges with --head" "0|yes" "${rc}|$(grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit ${H3}" "${ROOT}/gh.log" && echo yes)"
is "the base-merged head merges with --head: base-merged, then merge ok" "merge s base-merged ${H3}|merge s ok" \
  "$(events | grep '^merge ' | paste -sd'|' -)"

finish "merge base-update"

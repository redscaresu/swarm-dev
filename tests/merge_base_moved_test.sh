#!/usr/bin/env bash
# merge_base_moved_test.sh — swarm.sh merge runs no pr merge of the head of a story PR, green on its head, whose
# base gained a commit changing a path off the board after the head's CI ran (compare <head>...<base>):
# it merges the base into the PR's branch, says base merged:, and merges the new head once it is green
# (merge_base_update_test.sh and merge_base_update_wait_test.sh have the rest of that). A board-only
# gain, an up-to-date head and a base with a merge queue merge the head as it is. A
# transient compare error is read again; any other, and a board repo it cannot read, refuse naming it.
# On merge_fixture.sh, whose stub serves that compare from ${FX}/behind (nothing behind without one).
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
# Merging the base in waits for the new head's CI, whose first read also reads its workflows: 60 s for it.
# shellcheck disable=SC2034 # merge_fixture.sh's merge reads it
MERGE_CI=60

# gained <n> <path>... — the base has <n> commits the head lacks, changing <path>s.
gained() {
  local n="$1" p l=""; shift
  for p in "$@"; do l+="${l:+,}{\"filename\":\"${p}\",\"status\":\"modified\"}"; done
  echo "{\"ahead_by\":${n},\"files\":[${l}]}" > "${FX}/behind"
}
compared() { grep -qxF "api repos/$1/compare/$2...main" "${ROOT}/gh.log"; }
not_compared() { ! grep -qF "/compare/${H1}...main" "${ROOT}/gh.log"; }
H3=3333333333333333333333333333333333333333; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# updates [head] — GitHub merges main, at ${B}, into the PR's branch at [head] (${H1}), as web-flow with its
# signature verified: its head becomes ${H3}, which has a green check and is up to date with main.
updates() {
  echo '{"message":"Updating pull request branch."}' > "${FX}/update"; echo "${H3}" > "${FX}/update-head"
  echo '{"ahead_by":0,"files":[]}' > "${FX}/behind.${H3}"
  checks "${FX}/${H3}.checks" "$(run test completed success)"; statuses "${FX}/${H3}.status"
  printf '{"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}},"parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "${1:-${H1}}" "${B}" > "${FX}/commit.${H3}"
  printf '{"commit":{"sha":"%s"}}\n' "${B}" > "${FX}/basehead"
  # What the merge changes is what main brings.
  local x='{"files":[{"filename":"bin/x.sh","status":"modified","sha":"b1","patch":"@@ -1 +1 @@\n-a\n+b"}]}'
  echo "${x}" > "${FX}/compare.${1:-${H1}}...${H3}"; echo "${x}" > "${FX}/compare.${1:-${H1}}...${B}"
  # The PR's own change, which the merge leaves alone.
  echo '{"files":[{"filename":"bin/pr.sh","status":"modified","sha":"p1"}]}' > "${FX}/compare.${B}...${1:-${H1}}"
}
updated() { grep -qxF "api -X PUT -f expected_head_sha=${H1} repos/$1/pulls/7/update-branch" "${ROOT}/gh.log"; }
MOVED="base merged: ${URL} is now 3333333 (1111111 with main merged in); waiting up to 60s for its CI"
# merged_in <name> [text] — the last merge said main merged in (${MOVED}, or [text]), and merged ${H3},
# never the head it was asked to merge.
merged_in() {
  is "$1: exits 0" 0 "${rc}"
  check "$1: says ${2:-${MOVED}}" said "${2:-${MOVED}}"
  is "$1: merges the new head, not the old" "yes|no" \
    "$(grep -qF -- "--match-head-commit ${H3}" "${ROOT}/gh.log" && echo yes || echo no)|$(grep -qF -- "--match-head-commit ${H1}" "${ROOT}/gh.log" && echo yes || echo no)"
}

# --- The base gained code after the head's CI ran: merge merges the base in, and merges the new head, not the old.
fresh; gained 1 bin/x.sh; updates; merge "${URL}"
merged_in "the base gained bin/x.sh"
check "the base gained bin/x.sh: compares the head with the base" compared o/r "${H1}"
check "the base gained bin/x.sh: asks GitHub to merge main in, pinned to the head" updated o/r
check "the base gained bin/x.sh: logs base-merged" logged "^merge s base-merged ${H3}$"
fresh; gained 2 docs/stories/t.md bin/x.sh; updates; merge "${URL}"
merged_in "the base gained a board file and bin/x.sh"
fresh; echo '{"ahead_by":1,"files":[{"filename":"docs/stories/t.md","previous_filename":"bin/x.sh","status":"renamed"}]}' > "${FX}/behind"
updates; merge "${URL}"; merged_in "the base renamed bin/x.sh onto the board"

# --- Board-only commits run no tests: they do not count, in the board's own repo.
fresh; gained 1 docs/stories/t.md docs/epics/e.md; merge "${URL}"
is "the base gained only board files: exits 0" 0 "${rc}"
check "the base gained only board files: merges" merged
fresh; gained 1 docs/stories/README.md; updates; merge "${URL}"
merged_in "a board README counts as code: a test may check it"
fresh; gained 1 docs/stories.md; updates; merge "${URL}"
merged_in "a file beside the board's folders is not on it"
OTHER=https://github.com/o/other/pull/7
fresh; item s "status: review" "prs: ${OTHER}"; gained 1 docs/stories/t.md; updates; merge "${OTHER}"
merged_in "a PR in another repo: its stories/ file is code" "base merged: ${OTHER} is now 3333333 (1111111 with main merged in)"
check "a PR in another repo: compares in that repo" compared o/other "${H1}"
check "a PR in another repo: merges main in in that repo" updated o/other
# The board's repo cannot be read: the failed read is named, with gh's own line, not called code on the
# base, and the refusal says to merge the base in, which clears it.
NOREPO="GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)"
fresh; gained 1 docs/stories/t.md; echo "${NOREPO}" > "${FX}/origin.fail"; merge "${URL}"
refused "board files only, gh cannot read the board's repo" \
  "cannot tell whether main moved past 1111111's CI: its 1 commits change only board paths, and gh repo view failed (${NOREPO}): merge origin/main in, push, and merge the new head"
fresh; gained 1 docs/stories/t.md; echo 'not json' > "${FX}/origin"; merge "${URL}"
refused "board files only, gh names no repo" "and gh repo view named no GitHub repo: merge origin/main in, push, and merge the new head"
fresh; gained 1 docs/stories/t.md; git -C "${P}" remote remove origin; merge "${URL}"; git -C "${P}" remote add origin "${ROOT}/origin.git"
refused "board files only, the board's repo has no origin" \
  "its 1 commits change only board paths, and ${P}, the board's repo, has no origin: merge origin/main in, push, and merge the new head"

# --- A head up to date with the base merges.
fresh; merge "${URL}"
is "up to date: exits 0" 0 "${rc}"
check "up to date: compares the head with the base, then merges" compared o/r "${H1}"
check "up to date: merges" merged

# --- A compare it cannot read, or one that may be cut short, refuses and names it.
fresh; touch "${FX}/behind.fail"; merge "${URL}"
refused "a failed compare" "cannot tell whether main moved past 1111111's CI: gh api repos/o/r/compare/${H1}...main: gh: HTTP 502"
reads() { grep -c "/compare/${H1}...main" "${ROOT}/gh.log" || true; }
is "a failed compare: a 502 is transient, so it is read three times" 3 "$(reads)"
# One blip is read again, and the second read decides.
fresh; gained 1 bin/x.sh; updates; touch "${FX}/behind.1.fail"; merge "${URL}"
merged_in "a 502 on the first compare, code on the second"
fresh; echo '{"ahead_by":0,"files":[]}' > "${FX}/behind"; touch "${FX}/behind.1.fail"; merge "${URL}"
is "a 502 on the first compare, up to date on the second: merges after two reads" "0|yes|2" "${rc}|$(merged && echo yes)|$(reads)"
# A 404 is no blip: one read, then a refusal naming it.
fresh; echo "Not Found" > "${FX}/behind.404"; merge "${URL}"
refused "a 404 on the compare" "cannot tell whether main moved past 1111111's CI: gh api repos/o/r/compare/${H1}...main: gh: Not Found (HTTP 404)"
is "a 404 on the compare: read once" 1 "$(reads)"
# A read that hangs is cut at the wait, and merge refuses naming it.
fresh; touch "${FX}/behind.hang"; merge SWARM_BASE_MOVED_WAIT=2 "${URL}"
refused "a compare that hangs" "cannot tell whether main moved past 1111111's CI: the compare took over 2s"
fresh; gained 1 docs/stories/t.md; touch "${FX}/origin.hang"; merge SWARM_BASE_MOVED_WAIT=2 "${URL}"
refused "board files only, a board repo read that hangs" "and gh did not say within 2s which GitHub repo the board's origin is: merge origin/main in, push, and merge the new head"
fresh; echo '{"status":"ahead"}' > "${FX}/behind"; merge "${URL}"
refused "a compare with no ahead_by" "cannot tell whether main moved past 1111111's CI: unreadable compare"
# many <n> <prefix> — <n> paths, <prefix>1.md to <prefix><n>.md.
many() { local i; for ((i = 1; i <= $1; i++)); do echo "$2${i}.md"; done; }
# 300 board files: GitHub may have cut the list short, so a file off the board may be missing from it.
fresh; read -ra fs <<< "$(many 300 docs/stories/f | paste -sd' ' -)"; gained 1 "${fs[@]}"; merge "${URL}"
refused "a compare listing 300 board files" "lists 300 files, so it may be cut short: merge origin/main in, push, and merge the new head"
fresh; gained 1; merge "${URL}"
refused "a compare listing no file for its commits" "the compare of 1111111 with main lists no file for 1 commit(s): merge origin/main in, push, and merge the new head"
fresh; read -ra fs <<< "$(many 299 docs/stories/f | paste -sd' ' -)"; gained 1 "${fs[@]}"; merge "${URL}"
is "a compare listing 299 board files: exits 0" 0 "${rc}"

# --- A merge queue tests the combination: no compare is read.
fresh; gained 1 bin/x.sh; echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"
printf '{"data":{"repository":{"pullRequest":{"id":"PR_7","state":"MERGED","headRefOid":"%s","isInMergeQueue":false,"autoMergeRequest":null,"mergeCommit":{"oid":"%s"},"mergeQueueEntry":null,"timelineItems":{"nodes":[]}}}}}\n' \
  "${H1}" "${M}" > "${FX}/queue"
merge "${URL}"
is "a merge queue: exits 0" 0 "${rc}"
check "a merge queue: enqueued" grep -qxF "pr merge 7 --repo o/r --auto --match-head-commit ${H1}" "${ROOT}/gh.log"
check "a merge queue: no compare read" not_compared
# --board and --release never read it.
fresh; rm "${S}"; gained 1 bin/x.sh; merge --board "${URL}"
is "--board: exits 0" 0 "${rc}"
check "--board: no compare read" not_compared

# --- v0.28.0: PR A and PR B are each green on the old base. A merges and changes bin/a.sh; B's head is
# then not merged: merge merges main into it, and that new head merges. B's PR reads open while A's reconcile runs.
URL_B=https://github.com/o/r/pull/8
fresh; item b "status: review" "prs: ${URL_B}"; echo OPEN > "${FX}/state.8"
echo "echo '{\"ahead_by\":1,\"files\":[{\"filename\":\"bin/a.sh\",\"status\":\"modified\"}]}' > '${FX}/behind'" > "${FX}/on-merge"
merge "${URL}"
is "v0.28.0: A merges" "0|yes" "${rc}|$(merged && echo yes)"
# B's PR reads open from here on, as the fixture's one PR state.
rm "${FX}/state.8"; echo OPEN > "${FX}/state"; echo null > "${FX}/mergecommit"; : > "${ROOT}/gh.log"; echo "${H2}" > "${FX}/head"
checks "${FX}/${H2}.checks" "$(run test completed success)"; statuses "${FX}/${H2}.status"
updates "${H2}"; merge "${URL_B}"
check "v0.28.0: main is merged into B" said "base merged: ${URL_B} is now 3333333 (2222222 with main merged in)"
check "v0.28.0: B compared its head with the base" compared o/r "${H2}"
check "v0.28.0: B's branch had main merged in at its head" grep -qxF "api -X PUT -f expected_head_sha=${H2} repos/o/r/pulls/8/update-branch" "${ROOT}/gh.log"
is "v0.28.0: B's new head, with main merged in, merges, and B's old head does not" "0|8 ${H3}|no" \
  "${rc}|$(sed -n 's/^pr merge \([0-9]*\) .*--match-head-commit \([0-9a-f]*\)$/\1 \2/p' "${ROOT}/gh.log")|$(grep -qF -- "--match-head-commit ${H2}" "${ROOT}/gh.log" && echo yes || echo no)"

finish "merge base-moved"

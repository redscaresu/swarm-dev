#!/usr/bin/env bash
# merge_base_moved_test.sh — swarm.sh merge refuses a story PR, green on its head, whose base gained a
# commit changing a path off the board after the head's CI ran (compare <head>...<base>), and runs no
# pr merge; a board-only gain, an up-to-date head and a base with a merge queue merge. A transient
# compare error is read again; any other, and a board repo it cannot read, refuse naming it. On
# merge_fixture.sh, whose stub serves that compare from ${FX}/behind (nothing behind without one).
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

# gained <n> <path>... — the base has <n> commits the head lacks, changing <path>s.
gained() {
  local n="$1" p l=""; shift
  for p in "$@"; do l+="${l:+,}{\"filename\":\"${p}\",\"status\":\"modified\"}"; done
  echo "{\"ahead_by\":${n},\"files\":[${l}]}" > "${FX}/behind"
}
compared() { grep -qxF "api repos/$1/compare/$2...main" "${ROOT}/gh.log"; }
not_compared() { ! grep -qF "/compare/${H1}...main" "${ROOT}/gh.log"; }
MOVED="the base main moved past 1111111's CI (1 commits it lacks): merge origin/main in, push, and merge the new head"

# --- The base gained code after the head's CI ran: refused before pr merge.
fresh; gained 1 bin/x.sh; merge "${URL}"
refused "the base gained bin/x.sh" "${MOVED}"
check "the base gained bin/x.sh: compares the head with the base" compared o/r "${H1}"
check "the base gained bin/x.sh: logs the refusal" logged "^merge s ${MOVED}$"
check "the base gained bin/x.sh: the story stays in review" grep -qx "status: review" "${S}"
fresh; gained 2 docs/stories/t.md bin/x.sh; merge "${URL}"
refused "the base gained a board file and bin/x.sh" "moved past 1111111's CI (2 commits it lacks)"
fresh; echo '{"ahead_by":1,"files":[{"filename":"docs/stories/t.md","previous_filename":"bin/x.sh","status":"renamed"}]}' > "${FX}/behind"
merge "${URL}"; refused "the base renamed bin/x.sh onto the board" "${MOVED}"

# --- Board-only commits run no tests: they do not count, in the board's own repo.
fresh; gained 1 docs/stories/t.md docs/epics/e.md; merge "${URL}"
is "the base gained only board files: exits 0" 0 "${rc}"
check "the base gained only board files: merges" merged
fresh; gained 1 docs/stories/README.md; merge "${URL}"
refused "a board README counts as code: a test may check it" "${MOVED}"
fresh; gained 1 docs/stories.md; merge "${URL}"
refused "a file beside the board's folders is not on it" "${MOVED}"
OTHER=https://github.com/o/other/pull/7
fresh; item s "status: review" "prs: ${OTHER}"; gained 1 docs/stories/t.md; merge "${OTHER}"
refused "a PR in another repo: its stories/ file is code" "${MOVED}"
check "a PR in another repo: compares in that repo" compared o/other "${H1}"
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
fresh; gained 1 bin/x.sh; touch "${FX}/behind.1.fail"; merge "${URL}"
refused "a 502 on the first compare, code on the second" "${MOVED}"
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

# --- v0.28.0: PR A and PR B are each green on the old base. A merges and changes bin/a.sh; B is then
# refused, and its head with the base merged in merges. B's PR reads open while A's reconcile runs.
URL_B=https://github.com/o/r/pull/8
fresh; item b "status: review" "prs: ${URL_B}"; echo OPEN > "${FX}/state.8"
echo "echo '{\"ahead_by\":1,\"files\":[{\"filename\":\"bin/a.sh\",\"status\":\"modified\"}]}' > '${FX}/behind'" > "${FX}/on-merge"
merge "${URL}"
is "v0.28.0: A merges" "0|yes" "${rc}|$(merged && echo yes)"
# B's PR reads open from here on, as the fixture's one PR state.
rm "${FX}/state.8"; echo OPEN > "${FX}/state"; echo null > "${FX}/mergecommit"; : > "${ROOT}/gh.log"; echo "${H2}" > "${FX}/head"
checks "${FX}/${H2}.checks" "$(run test completed success)"; statuses "${FX}/${H2}.status"
merge "${URL_B}"
is "v0.28.0: B, green on the old base, exits non-zero" 1 "${rc}"
check "v0.28.0: B is refused, naming the moved base" said "the base main moved past 2222222's CI (1 commits it lacks): merge origin/main in, push, and merge the new head"
check "v0.28.0: no pr merge of B" not_merged
check "v0.28.0: B compared its head with the base" compared o/r "${H2}"
H3=3333333333333333333333333333333333333333
echo "${H3}" > "${FX}/head"; checks "${FX}/${H3}.checks" "$(run test completed success)"; statuses "${FX}/${H3}.status"
rm "${FX}/behind"; merge --head "${H3}" "${URL_B}"
is "v0.28.0: B's new head, with main merged in, merges" "0|yes" "${rc}|$(merged && echo yes)"

finish "merge base-moved"

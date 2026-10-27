#!/usr/bin/env bash
# merge_protected_hold_test.sh — with merge = agent, swarm.sh merge holds a story PR that changes a
# protected path (.claude/, .github/, hooks/ or a root Makefile, GNUmakefile or makefile, in any case of
# letters, a renamed or removed file's old path too) for the user, reading the PR's files at the pinned
# head (compare <base>...<head>) after the story lookup and the head's CI check. A read that fails holds
# it too, saying why: a transient gh error is read again, a 404 is not, a hung read stops at
# BASE_MOVED_WAIT, and a PR of over 300 files or of no file is never listed. A PR that changes none of
# the paths merges, a --board PR reads no compare, and under merge = human merge_grant still refuses one
# under an HLD granting merge. On merge_fixture.sh, whose gh stub answers compare/main...<head> with
# ${FX}/compare.main, else the PR's files.
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

OK="merge s ok|main-ci s ok|reconcile s ok (finished)"
# changes <path>... — the PR's files: story s's file and each <path>, all modified.
changes() {
  local p list='{"filename":"docs/stories/s.md","status":"modified"}'
  for p in "$@"; do list+=",{\"filename\":\"${p}\",\"status\":\"modified\"}"; done
  echo "[${list}]" > "${FX}/files"; echo $(($# + 1)) > "${FX}/nfiles"
}
pinned_read() { grep -qF "repos/o/r/compare/main...${H1}" "${ROOT}/gh.log"; }
compare_reads() { grep -cF "repos/o/r/compare/main...${H1}" "${ROOT}/gh.log" || true; }
# held_s <name> <path> — the last merge held story s for <path>, and logged it.
held_s() {
  refused "$1" "held: s changes $2, which only the user merges; the user merges it"
  check "$1: events.tsv has merge s held:" logged "^merge s held: s changes $2"
}

# --- Each protected path holds the story's PR, naming the path, with no merge and a held event; the
# case of its letters does not matter.
for p in hooks/x.sh .github/workflows/ci.yml .claude/settings.json Makefile GNUmakefile makefile .CLAUDE/settings.json Hooks/x.sh MAKEFILE; do
  fresh; changes "${p}"; merge "${URL}"
  held_s "a story PR changing ${p}" "${p}"
  check "a story PR changing ${p}: read its files at the pinned head" pinned_read
done

# --- A file renamed out of hooks/, or removed from it, holds it, naming its old path.
fresh; changes; echo 2 > "${FX}/nfiles"
echo '{"files":[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"bin/x.sh","status":"renamed","previous_filename":"hooks/x.sh"}]}' > "${FX}/compare.main"
merge "${URL}"; held_s "a story PR renaming hooks/x.sh to bin/x.sh" hooks/x.sh
fresh; echo '[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"hooks/x.sh","status":"removed"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge "${URL}"; held_s "a story PR removing hooks/x.sh" hooks/x.sh

# --- Paths outside them merge: the pattern is anchored at the root.
for p in bin/x.sh sub/Makefile docs/hooks/x.md; do
  fresh; changes "${p}"; merge "${URL}"
  is "a story PR changing ${p} merges" "${OK}" "$(events | paste -sd'|' -)"
  check "a story PR changing ${p}: gh pr merge ran" merged
done

# --- A file list it cannot read at the pin holds the PR (fails closed), saying why.
fresh; changes bin/x.sh; touch "${FX}/compare.fail"; merge "${URL}"
refused "a story PR whose files at the pin cannot be read" "held: s (its files at ${H1:0:7} could not be read"
check "a story PR whose files at the pin cannot be read: says so, and that the user merges it" \
  said "so whether it changes a path only the user merges is unknown); the user merges it"
check "a story PR whose files at the pin cannot be read: events.tsv has merge s held:" logged '^merge s held: s (its files'
is "a story PR whose files at the pin cannot be read: a 502 is read three times" 3 "$(compare_reads)"
# A transient error on the first read, then the list: the PR merges.
fresh; changes bin/x.sh; echo "{\"files\":$(cat "${FX}/files")}" > "${FX}/compare.main"; touch "${FX}/compare.main.1.fail"; merge "${URL}"
is "a story PR whose first compare read fails with a 502 merges on the second" "${OK}" "$(events | paste -sd'|' -)"
is "a story PR whose first compare read fails with a 502: two compare reads" 2 "$(compare_reads)"
# A 404 is no transient error: held at once.
fresh; changes bin/x.sh; echo 'Not Found' > "${FX}/compare.main.404"; merge "${URL}"
refused "a story PR whose compare is a 404" "held: s (its files at ${H1:0:7} could not be read"
check "a story PR whose compare is a 404: names the 404" said "HTTP 404"
is "a story PR whose compare is a 404: one compare read, no retry" 1 "$(compare_reads)"
# A read that hangs stops at BASE_MOVED_WAIT and holds.
fresh; changes bin/x.sh; touch "${FX}/compare.hang"; merge SWARM_BASE_MOVED_WAIT=2 "${URL}"
refused "a story PR whose compare hangs" "held: s (its files at ${H1:0:7} could not be read: the compare took over 2s"
# Fewer files at the pin than the PR changes is a list it cannot read too, and it says how many.
fresh; changes bin/x.sh; echo 3 > "${FX}/nfiles"; merge "${URL}"
refused "a story PR whose pinned compare lists fewer files than it changes" "held: s (its files at ${H1:0:7} could not be read: the compare of main with ${H1:0:7} lists 2 of the 3 files the PR changes"
# Over 300 files, or none: never listed, so the hold says it stands, with no read.
fresh; changes bin/x.sh; echo 301 > "${FX}/nfiles"; merge "${URL}"
refused "a story PR of 301 files" "held: s (its files at ${H1:0:7} could not be read: the compare of main with ${H1:0:7} lists at most 300 files, and the PR changes 301, so it cannot list them all"
is "a story PR of 301 files: no compare read" 0 "$(compare_reads)"
fresh; echo '[]' > "${FX}/files"; echo 0 > "${FX}/nfiles"; merge "${URL}"
refused "a story PR of no file" "held: s (its files at ${H1:0:7} could not be read: the PR changes no file"
# The PR's files API lists a later head's harmless files; the pinned head adds hooks/x.sh.
fresh; changes bin/x.sh
echo '{"files":[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"hooks/x.sh","status":"added"}]}' > "${FX}/compare.main"
merge "${URL}"; refused "a story PR whose pinned head adds hooks/x.sh behind a harmless later file list" "held: s changes hooks/x.sh"

# --- The hold runs after the story lookup and the head's CI check: those refusals come first, with no read.
fresh; rm "${S}"; changes hooks/x.sh; merge "${URL}"
refused "a PR no story lists, changing hooks/x.sh" "no story or epic lists ${URL} on its prs: line: run swarm.sh review"
is "a PR no story lists, changing hooks/x.sh: no compare read" 0 "$(compare_reads)"
fresh; changes hooks/x.sh; item s "status: ready" "prs: ${URL}"; merge "${URL}"
refused "a PR whose story is not in review, changing hooks/x.sh" "s is ready, not review"
is "a PR whose story is not in review, changing hooks/x.sh: no compare read" 0 "$(compare_reads)"
fresh; changes hooks/x.sh; checks "${FX}/${H1}.checks" "$(run test completed failure)"; merge "${URL}"
refused "a PR with a red head, changing hooks/x.sh" "the head ${H1:0:7} is not green"
is "a PR with a red head, changing hooks/x.sh: no compare read" 0 "$(compare_reads)"

# --- A --board PR under merge = agent reads no compare of main with its head.
fresh; merge --board "${URL}"
check "a --board PR under merge = agent: gh pr merge ran" merged
is "a --board PR under merge = agent: no compare of main with the head" 0 "$(compare_reads)"

# --- merge = human: an HLD granting merge does not cover a protected path, and the hold reads no files.
# granted — merge = human; story s in review under epic g, under agreed HLD h granting merge.
granted() {
  fresh "merge = human"; mkdir -p "${P}/docs/hld" "${P}/docs/epics"
  printf -- '---\nstatus: agreed\ngrants: [merge]\n---\n\n# h\n' > "${P}/docs/hld/h.md"
  printf -- '---\nstatus: active\nhld: h\n---\n\n# g\n' > "${P}/docs/epics/g.md"
  item s "status: review" "prs: ${URL}" "epic: g"
}
granted; changes hooks/x.sh; merge "${URL}"
refused "merge = human, granted, a story PR changing hooks/x.sh" "${URL} waits on the user's merge (merge = human, and no HLD grants merge for it)"
granted; changes bin/x.sh; merge "${URL}"
is "merge = human, granted, a story PR changing bin/x.sh merges" "${OK}" "$(events | paste -sd'|' -)"
is "merge = human, granted: one pinned compare read, the grant's" 1 "$(compare_reads)"
rm -rf "${P}/docs/hld" "${P}/docs/epics"

finish "merge protected hold"

#!/usr/bin/env bash
# merge_protected_hold_test.sh — with merge = agent, swarm.sh merge holds a story PR that changes a
# protected path (.claude/, .github/, hooks/ or a root Makefile, GNUmakefile or makefile, a renamed
# file's old path too) for the user, reading the PR's files at the pinned head (compare
# <base>...<head>), and holds it when that read fails. A PR that changes none of them merges, and
# under merge = human merge_grant still refuses one under an HLD granting merge. On merge_fixture.sh,
# whose gh stub answers compare/main...<head> with ${FX}/compare.main, else the PR's files.
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

# --- Each protected path holds the story's PR, naming the path, with no merge and a held event.
for p in hooks/x.sh .github/workflows/ci.yml .claude/settings.json Makefile; do
  fresh; changes "${p}"; merge "${URL}"
  refused "a story PR changing ${p}" "held: s changes ${p}, which only the user merges; the user merges it"
  check "a story PR changing ${p}: events.tsv has merge s held:" logged "^merge s held: s changes ${p}"
  check "a story PR changing ${p}: read its files at the pinned head" pinned_read
done

# --- A file renamed out of hooks/ holds it, naming its old path.
fresh; changes; echo 2 > "${FX}/nfiles"
echo '{"files":[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"bin/x.sh","status":"renamed","previous_filename":"hooks/x.sh"}]}' > "${FX}/compare.main"
merge "${URL}"; refused "a story PR renaming hooks/x.sh to bin/x.sh" "held: s changes hooks/x.sh, which only the user merges"
check "a story PR renaming hooks/x.sh to bin/x.sh: events.tsv has merge s held:" logged '^merge s held: s changes hooks/x.sh'

# --- Paths outside them merge: the pattern is anchored at the root.
for p in bin/x.sh sub/Makefile docs/hooks/x.md; do
  fresh; changes "${p}"; merge "${URL}"
  is "a story PR changing ${p} merges" "${OK}" "$(events | paste -sd'|' -)"
  check "a story PR changing ${p}: gh pr merge ran" merged
done

# --- A file list it cannot read at the pin holds the PR (fails closed).
fresh; changes bin/x.sh; touch "${FX}/compare.fail"; merge "${URL}"
refused "a story PR whose files at the pin cannot be read" "held: s (its files at ${H1:0:7} could not be read"
check "a story PR whose files at the pin cannot be read: says so, and that the user merges it" \
  said "so whether it changes a path only the user merges is unknown); the user merges it"
check "a story PR whose files at the pin cannot be read: events.tsv has merge s held:" logged '^merge s held: s (its files'
# Fewer files at the pin than the PR changes is a list it cannot read too.
fresh; changes bin/x.sh; echo 3 > "${FX}/nfiles"; merge "${URL}"
refused "a story PR whose pinned compare lists fewer files than it changes" "held: s (its files at ${H1:0:7} could not be read"
# The PR's files API lists a later head's harmless files; the pinned head adds hooks/x.sh.
fresh; changes bin/x.sh
echo '{"files":[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"hooks/x.sh","status":"added"}]}' > "${FX}/compare.main"
merge "${URL}"; refused "a story PR whose pinned head adds hooks/x.sh behind a harmless later file list" "held: s changes hooks/x.sh"

# --- merge = human: an HLD granting merge does not cover a protected path, and merge_hold reads no files.
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

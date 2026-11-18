#!/usr/bin/env bash
# merge_pull_forward_test.sh — once swarm.sh merge has had GitHub merge the base into a story PR's
# branch, it brings the builder's worktree to the new head before it returns, refusal or not: a clean
# worktree at the old head is fetched and fast-forwarded (pulled:), and any other worktree is left as
# it is while its builder gets a nudge naming the new head (nudged:, queued for a busy builder). A
# board PR's merge touches no worktree and nudges nobody. On merge_fixture.sh, with real commits here:
# story s's branch in the fixture's origin, its worktree beside the project (proj-wt/s), and GitHub's
# merge of main into it made in another clone, so only a fetch brings it to the worktree.
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

# herdr: the fixture's, except that agent list shows s, story s's builder, working in pane w:s (a busy
# builder: its tell is queued, not sent).
printf 'w:s s\n' >> "${P}/.swarm/state/e"
mv "${ROOT}/bin/herdr" "${ROOT}/bin/herdr-fixture"
cat > "${ROOT}/bin/herdr" <<STUB
#!/bin/sh
if [ "\$1 \$2" = "agent list" ]; then
  "${ROOT}/bin/herdr-fixture" "\$@" | sed 's/"name":"s","agent_status":"idle"/"name":"s","agent_status":"working"/'
  exit
fi
exec "${ROOT}/bin/herdr-fixture" "\$@"
STUB
chmod +x "${ROOT}/bin/herdr"
printf 'conduct-e w:c\nt w:b\ns w:s\n' > "${ROOT}/agents"

GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgSign=false)
WT="${ROOT}/proj-wt/s"; Q="${P}/.swarm/tells"
# The real commits: main's first commit, then story s's commit on story/s (H1, the PR's head), then in
# another clone main's next commit (B) and GitHub's merge of it into story/s (H3), both pushed to origin.
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m base
"${GIT[@]}" -C "${P}" push -q origin HEAD:refs/heads/main
"${GIT[@]}" -C "${P}" branch -q story/s
"${GIT[@]}" -C "${P}" worktree add -q "${WT}" story/s
echo pr > "${WT}/pr.txt"; "${GIT[@]}" -C "${WT}" add pr.txt; "${GIT[@]}" -C "${WT}" commit -q -m pr
"${GIT[@]}" -C "${WT}" push -q origin story/s
H1="$(git -C "${WT}" rev-parse HEAD)"
# --branch main: origin's HEAD names git's default branch, which may not be main.
"${GIT[@]}" clone -q --branch main "${ROOT}/origin.git" "${ROOT}/github"
echo x > "${ROOT}/github/x.txt"; "${GIT[@]}" -C "${ROOT}/github" add x.txt; "${GIT[@]}" -C "${ROOT}/github" commit -q -m main
B="$(git -C "${ROOT}/github" rev-parse HEAD)"
"${GIT[@]}" -C "${ROOT}/github" checkout -q story/s
"${GIT[@]}" -C "${ROOT}/github" merge -q --no-edit main
H3="$(git -C "${ROOT}/github" rev-parse HEAD)"
"${GIT[@]}" -C "${ROOT}/github" push -q origin main story/s
is "the fixture: H3 is a merge of H1 and B" "${H1} ${B}" "$(git -C "${ROOT}/github" rev-parse "${H3}^1" "${H3}^2" | paste -sd' ' -)"
not_in_worktree() { ! git -C "${WT}" cat-file -e "${H3}^{commit}" 2>/dev/null; }
check "the fixture: H3 is not in the worktree, so only a fetch brings it" not_in_worktree

# moved — fresh, and main gained bin/x.sh after ${H1}'s CI ran; GitHub's merge of main into the PR's
# branch makes ${H3}, a merge of ${H1} and ${B} (main's head), as web-flow with its signature verified,
# that changes only bin/x.sh. ${H3}'s one check is red, so the merge refuses after the base merge. The
# worktree is at ${H1} with nothing uncommitted, and no tell is queued; story s's tell check counts as
# running (this test's own pid), so a queued tell starts none.
moved() {
  local x='{"filename":"bin/x.sh","status":"modified","sha":"b1"}'
  fresh
  echo "{\"ahead_by\":1,\"files\":[${x}]}" > "${FX}/behind.${H1}"
  echo "${H3}" > "${FX}/update-head.${H1}"; echo '{"message":"Updating pull request branch."}' > "${FX}/update"
  printf '{"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}},"parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "${H1}" "${B}" > "${FX}/commit.${H3}"
  echo "{\"files\":[${x}]}" > "${FX}/compare.${H1}...${H3}"; echo "{\"files\":[${x}]}" > "${FX}/compare.${H1}...${B}"
  echo '{"files":[{"filename":"bin/pr.sh","status":"modified","sha":"p1"}]}' > "${FX}/compare.${B}...${H1}"
  printf '{"commit":{"sha":"%s"}}\n' "${B}" > "${FX}/basehead"
  checks "${FX}/${H3}.checks" "$(run test completed failure)"; statuses "${FX}/${H3}.status"
  "${GIT[@]}" -C "${WT}" reset -q --hard "${H1}"
  rm -rf "${Q}"; mkdir -p "${Q}"; echo "$(date +%s) test $$" > "${Q}/s.later"
}
at() { git -C "${WT}" rev-parse HEAD; }
# no_update_after_first — gh.log has one update-branch request, the first run's.
no_update_after_first() { [[ "$(grep -c update-branch "${ROOT}/gh.log")" == 1 ]]; }
# nudges — how many nudge tells are queued for s (one at most: a newer one replaces it).
nudges() { if [[ -e "${Q}/s.nudge" ]]; then echo 1; else echo 0; fi; }
# merge_here — the fixture's merge from the lead's pane inside herdr, so swarm.sh tell can reach herdr.
merge_here() { merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "$@"; }

# --- A clean worktree at the old head: merge refuses on the red head and leaves the worktree at it.
moved; merge_here "${URL}"
is "a clean worktree: merge refuses on the red new head" 1 "${rc}"
check "a clean worktree: refusal is base merged, red" said "base merged, red: "
check "a clean worktree: the refusal still says to pull first" said "the builder pulls its branch (git pull --ff-only) before it pushes"
is "a clean worktree: is at GitHub's merge after the run" "${H3}" "$(at)"
check "a clean worktree: says so" said "pulled: s's worktree ${WT} is now at ${H3:0:7}, fast-forwarded from ${H1:0:7} to GitHub's merge of main"
is "a clean worktree: no nudge" 0 "$(nudges)"
is "a clean worktree: still nothing uncommitted" "" "$(git -C "${WT}" status --porcelain)"

# --- A rerun on a head an earlier run made (its base-merged line), whose worktree was left behind: the
# head is red, so merge refuses at its first check of the head, and the worktree is at the head by then.
"${GIT[@]}" -C "${WT}" reset -q --hard "${H1}"; echo "${H3}" > "${FX}/head"; merge_here "${URL}"
is "a rerun on a red earlier head: refuses at the head's own check" 1 "${rc}"
check "a rerun on a red earlier head: says the head is not green" said "the head ${H3:0:7} is not green"
check "a rerun on a red earlier head: asks GitHub for no merge" no_update_after_first
is "a rerun on a red earlier head: the worktree is at the head" "${H3}" "$(at)"
check "a rerun on a red earlier head: says so" said "pulled: s's worktree ${WT} is now at ${H3:0:7}, fast-forwarded from ${H1:0:7}"

# --- Uncommitted work: merge leaves the worktree as it was and queues one nudge naming the new head.
moved; echo edit >> "${WT}/pr.txt"; merge_here "${URL}"
is "uncommitted work: merge refuses on the red new head" 1 "${rc}"
is "uncommitted work: the worktree stays at the old head" "${H1}" "$(at)"
is "uncommitted work: the change is kept" " M pr.txt" "$(git -C "${WT}" status --porcelain)"
is "uncommitted work: one nudge queued for s" 1 "$(nudges)"
check "uncommitted work: the nudge names the new head" grep -qF "its head is now ${H3}" "${Q}/s.nudge"
check "uncommitted work: the nudge says why and to pull the branch" grep -qF "it has uncommitted changes. Before your next push, run git pull --ff-only origin story/s" \
  <(tr '\n' ' ' < "${Q}/s.nudge" | sed 's/  */ /g')
check "uncommitted work: says it nudged" said "nudged: s's builder to pull ${H3:0:7} into its worktree (it has uncommitted changes): queued: s (busy)"
check "uncommitted work: logged as a nudge tell" logged "^tell:nudge s queued: s"
"${GIT[@]}" -C "${WT}" checkout -q -- pr.txt

# --- A worktree at another commit (a local commit since the old head): left there, and nudged.
moved; echo more >> "${WT}/pr.txt"; "${GIT[@]}" -C "${WT}" commit -q -am local; local_head="$(at)"; merge_here "${URL}"
is "a local commit: the worktree stays at it" "${local_head}" "$(at)"
check "a local commit: says it nudged, naming where it is" said "nudged: s's builder to pull ${H3:0:7} into its worktree (it is at ${local_head:0:7}, not ${H1:0:7})"
is "a local commit: one nudge queued for s" 1 "$(nudges)"

# --- A board PR: its merge touches no worktree and nudges nobody, even with story s's PR behind.
moved; rm -f "${FX}/update-head.${H1}"; merge_here --board "${URL}"
is "a board PR: merges" 0 "${rc}"
is "a board PR: the worktree stays at the old head" "${H1}" "$(at)"
is "a board PR: no nudge" 0 "$(nudges)"
no_pull_line() { ! grep -qE '^(pulled|nudged): ' "${ROOT}/out"; }
no_update() { ! grep -q update-branch "${ROOT}/gh.log"; }
check "a board PR: no pulled: or nudged: line" no_pull_line
check "a board PR: no update-branch" no_update

finish "merge pull-forward"

---
kind: code
status: blocked
epic: release-client
depends_on: [plugin-id]
needs: plugin-id: its edit of docs/reference-merging.md § Releases at :1182-1183, the line after the wait sentence this changes, and its -pre block in tests/merge_rules_test.sh, which calls own_release.
touches: [bin/lib/merge.sh:release_confirmed, bin/lib/merge.sh:release_upgrade (its release_confirmed warning, :2708-2709), bin/lib/merge.sh:RELEASE_WAIT constants (a ref name beside it, :28), tests/merge_fixture.sh:gh stub (the git/ref/heads row), tests/merge_rules_test.sh:own_release, tests/merge_rules_test.sh:later-tag case (:479-480), tests/merge_rules_test.sh:release_confirmed cases (new, after :493), docs/reference-merging.md:Releases (the lead's check :1120-1121, the wait sentence :1181-1182, the warning sentence :1198-1200), commands/swarm.md:release arm (the merged: branch, :706-720)]
estimate_lines: 230
risk: high
---

# merge --release counts a release done only once its five files are uploaded and prerelease is at the tag's commit

Needs plugin-id: its edit of docs/reference-merging.md § Releases at :1182-1183, the line after the wait sentence this changes, and its -pre block in tests/merge_rules_test.sh, which calls the own_release this changes.
Carve-out story (HLD:486-490, P12). It changes release_confirmed, the release gate merge --release passes before it updates the plugin and moves agents, in bash. The user gave their go for it on 2026-11-22. The user merges it in a merge = human window: the lead sets merge = human, the user merges, the lead sets it back (the epic's Your part; this project runs merge = agent). Do not merge it.
Where: release_confirmed (bin/lib/merge.sh:2787-2802) returns 0 once tag v<version> is on the merge commit or a later base commit (release_on_base, :2810), and `gh api releases/tags/v<version>` .draft is False. It reads no asset and no branch.
release.yml attaches the five files, then publishes (which makes the tag), then moves prerelease last (.github/workflows/release.yml:161-208). So today merge --release can update the plugin after a failed attach, or before the move.
Change: two more conditions, read in the same loop, each gh call bounded by within release_left.
(a) The files. Before the loop, read the names once from `"${BASH}" "${SWARM_HOME}/scripts/build.sh" --list`, with binary_download's rules (bin/lib/binary.sh:569-600): --list runs, exactly one checksums line with sha256, at least one asset line, and every asset and checksums name matches BINARY_NAME_RE (binary.sh:543). Asset takes field 3, checksums field 2. A missing build.sh (as in v0.31.3's installed tree), a failed --list or any broken rule: release_confirmed fails at once, with no wait. It never stops merge under set -e. Each poll, the releases/tags read that gives .draft must also list every one of those names, by exact name, with state `uploaded`. No prefix match. Leave binary_download alone: the download code is binary-fetch's, and fetch-quarantine (#1135) edits it.
(b) The ref. `gh api repos/<repo>/git/ref/heads/prerelease` .object.sha, a 40-hex sha, equals the tag's commit. Equal, not ahead: release.yml moves prerelease to the pushed commit it tagged (:196-208), and a later release run moving it on means the update installs that later version, not v<new>. No compare read, so no stub default can answer for it. A failed or malformed read counts as not equal.
Name the branch once, as a constant beside RELEASE_WAIT (:28), matching release.yml's REF (:28). Stable is never checked: the workflow never moves it.
The --list is the running copy's. A release that drops a platform the old list names stays unconfirmed, and the warning says which file is missing.
Warnings, in release_upgrade (:2708-2709). Keep today's line byte-for-byte when the tag or the draft is what is unmet: `warning: no tag v<new> on the base at or after <sha7> with a published GitHub release, ...` (tests/merge_rules_test.sh:482,488 grep it). Add a line only for the new cases: the --list failure (naming build.sh --list and why), the missing or not-uploaded files (naming each), and prerelease (naming its sha7 and the tag's). Each keeps the hint (`run swarm.sh update, then <new> upgrade`).
RELEASE_WAIT stays 600 s and SWARM_RELEASE_WAIT stays. The copy's push-to-move took about 5 m 50 s (release-ci § release-publish-proof). merge --release waits for CI on the base before this clock starts, and the release run overlaps that wait.
No new SWARM_ name.
Real shapes first, before any fixture: read the copy once, read-only, and quote both reads in the PR.
- `gh api repos/redscaresu/swarm-dev-release-spike/releases/tags/v0.31.8 --jq '{draft, assets: [.assets[] | {name, state}]}'`. On 2026-11-22: draft false, five assets (SHA256SUMS, swarm-darwin-amd64, swarm-darwin-arm64, swarm-linux-amd64, swarm-linux-arm64), each `uploaded`.
- `gh api repos/redscaresu/swarm-dev-release-spike/git/ref/heads/prerelease`: {ref, node_id, url, object: {sha, type: commit, url}}, sha 097c6ca7 (v0.31.7's tag commit). v0.31.8's tag is aec9dfef, so the copy holds a real published release whose prerelease never got there.
The fixtures copy those shapes: field names, the five names, `uploaded`.
Tests: tests/merge_fixture.sh's gh stub serves releases/tags from ${FX}/release (:153). Add a row for */git/ref/heads/* from ${FX}/preref, before the */branches/* row (:155); serve already gives preref.fail, preref.<n> and a 404 when absent. No bin/ code reads git/ref/heads today. own_release (merge_rules_test.sh:378-381) writes the v0.31.8-shaped release and a preref at the tag's commit ${M}. The case at :479-480 (tag on ${H2}) writes preref at ${H2}. Check every other user of merge_fixture.sh still passes (tests that source it: grep -l merge_fixture.sh tests/).
New cases after :493, each asserting no claude call and no upgrade.log unless it says the plugin is updated:
- each of the five names absent in turn (a loop, SWARM_RELEASE_WAIT=0); each of the five with state `open` in turn; swarm-linux-amd64.bak present with swarm-linux-amd64 absent.
- the copy's real v0.31.8 state: all five uploaded, preref at another commit: refused, naming prerelease. Tag on ${H2} with preref at ${M}: refused (this is the case the stub's compare default hid).
- preref.fail; preref absent (404); preref with no 40-hex object.sha.
- a no-.git copy of the tree with scripts/build.sh removed; one whose build.sh --list prints no asset line; one whose --list exits 1. Each: refused at once, and the warning names --list.
- the files arriving on a later poll (release.1 missing one, release complete; SWARM_RELEASE_WAIT=2): the plugin is updated, and gh.log shows more than one releases/tags read.
- one case on the real scripts/build.sh: the warning for a release with no assets names all five, so the parse's field positions match the real --list.
Diff-run: the release_gates fixtures (tests/diff_fixtures_release_gates.sh:124-160) run with no tagref, so they stop at the tag and must show no difference. If one does differ, add scripts/allow/stage-1/release-done.md naming its exact lines (scripts/allow/README.md).
Docs, same PR:
- docs/reference-merging.md § Releases: the wait sentence (:1181-1182), the warning sentence (:1198-1200), and the lead's check after a release merge (:1120-1121, `checks that the tag and the GitHub release exist`): for swarm-dev's own repo, merge checks the five files and prerelease too.
- commands/swarm.md's release arm: `merge has confirmed the tag and the GitHub release` (:707-708), and the lead's by-hand check when merge stopped early (:719-720, `check the tag and the release`): the five files uploaded and prerelease at the tag's commit.
Each says a release counts done only with every file and with prerelease at the tag. Run the humanizer.
Mutations, on a worktree copy, each on its own: drop (a) (the absent-file loop goes red); check only this platform's asset (the loop goes red on the others); match names by prefix (the .bak case goes red); skip the state check (the `open` loop goes red); treat an empty --list as all present (the no-asset-line case goes red); drop (b) (the v0.31.8-state case goes red); accept any 40-hex preref (the ${H2}/${M} case goes red); accept a failed preref read (the preref.fail case goes red).

**Done when:**
- A published release with all five files uploaded and prerelease at the tag's commit: merge --release runs both claude updates, as today. Every existing release case in tests/merge_rules_test.sh passes, plugin-id's -pre block included, with the no-tag and draft warnings unchanged byte for byte.
- Each of the five files absent, and each with state `open`: no claude call, no upgrade, merge exits 0, and the warning names that file and the hint.
- swarm-linux-amd64.bak present with swarm-linux-amd64 absent counts as swarm-linux-amd64 missing.
- The copy's real v0.31.8 state (five uploaded, prerelease at another commit), the tag on ${H2} with prerelease at ${M}, a failed prerelease read, a 404 and a malformed sha: no claude call and no upgrade, and the warning names prerelease.
- No scripts/build.sh, a --list with no asset line, and a --list that exits 1: no claude call, the warning names --list, and gh.log shows no releases/tags poll after the first.
- Files that arrive on a later poll within SWARM_RELEASE_WAIT=2: the plugin is updated, and gh.log shows more than one releases/tags read.
- The PR quotes the two real reads of the copy, and the fixtures use their field names and values.
- tests/diff_run.sh's release_gates fixtures show no difference against the base, or scripts/allow/stage-1/release-done.md names each differing line.
- Each mutation turns its named case red on a worktree copy. The PR quotes the FAIL lines.
- docs/reference-merging.md § Releases (:1120-1121, :1181-1182, :1198-1200) and commands/swarm.md's release arm (:707-708, :719-720) say a release counts done only with its five files and prerelease at the tag. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

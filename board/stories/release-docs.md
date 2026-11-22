---
kind: docs
status: ready
epic: release-client
depends_on: []
touches: [AGENTS.md:patch rule (Rules that are not negotiable, :146-148), AGENTS.md:release paragraph (:343-348), README.md:Getting started (step 1), llms.txt:First steps (:5)]
estimate_lines: 30
easy: true
---

# AGENTS.md, README.md and llms.txt say a release reaches the prerelease machine at once and every other machine at the stage's end

Needs no other story. It states release-ci's behaviour, merged in #1118 to #1134.
The only story in this epic that edits AGENTS.md.
AGENTS.md patch rule (:146-148) says a loop fix 'ships as a patch release soon after it merges, so running projects get it'. It becomes: the release moves prerelease, so the machine on swarm-dev@swarm-dev-pre gets it at once, and every other machine gets it when the stage ends and the lead moves stable (HLD:71-74). docs/reference-merging.md:1088-1091 already says so. Keep the patch-gate lines (:149-151).
AGENTS.md release paragraph (:343-354) says 'Merging a version bump to main publishes the release and its v<version> tag' (:346-348). It also attaches the four binaries and SHA256SUMS, then moves prerelease, and never moves stable (release.yml:3-5, :28).
New sentences go on lines of their own. Lengthen no existing line.
README.md § Getting started step 1 (:62-66): the install command stays (HLD Goal 5). Add one line: it installs the stable release, which moves when a stage ends.
llms.txt:5: keep it in line with README's step 1. If nothing there is false, leave it and say so in the PR.
Leave alone: README.md § Updating and docs/running.md (update-runs-new-wrapper), docs/reference-merging.md (plugin-id, release-done), commands/swarm.md, docs/lead-by-hand.md (real-release-check).
Run the humanizer and say so in the PR.

**Done when:**
- AGENTS.md's patch rule names prerelease (at once) and stable (at the stage's end), and no longer says a patch reaches running projects when it merges.
- AGENTS.md's release paragraph says the workflow attaches the binaries and SHA256SUMS, then moves prerelease, and never moves stable.
- README.md step 1 says the install follows stable, which moves when a stage ends.
- tests/doc_check_test.sh passes.
- The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

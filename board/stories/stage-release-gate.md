---
kind: code
status: ready
epic: stage-gating
depends_on: []
touches: [bin/lib/dash.sh:DASH_NEXT input, bin/lib/dash_render.py:next row, bin/lib/board.sh:next_step release arm, bin/lib/board.sh:release_due, bin/lib/board.sh:release_stage (new helper), bin/lib/board.sh:next_report, tests/next_test.sh:expect_release whole output, tests/next_test.sh:release cases, docs/reference.md:Releases, README.md:Updating]
estimate_lines: 260
easy: false
---

# next holds a stage's release until every epic of that stage has left the board

Change next's release arm (bin/lib/board.sh:281-283). Only when release_due (:530-540) is due (dash runs next_step every frame), find the stage S: the lowest `stage: v<x.y.z>` above the tag's version among the board's epics (any status) and the epic files deleted from origin/<base>'s <board>/epics since the tag (the git log -z --diff-filter=D loop and `git show <c>^:<path>` of release_grant, bin/lib/merge.sh:1316-1325). A malformed stage: is ignored. No S, or a board outside the repo (BOARD_IN_REPO != 1): print `release` as today. S with no epic of stage S open on the board (open_item, :998): first line `release v<S>`, the why naming S. Otherwise print no release step: next goes on to the arms below, and next_report (:390-412) prints `release-held: v<S>, open epics: <slugs>, patches only` after the step's lines, as it does idle: lines. Make expect_release keep next's whole output (it keeps line 1 only, tests/next_test.sh:650). Use fixtures the later stage step leaves alone: an active stage epic with a story, not a draft with hld:. bash 3.2: compare versions field by field, no sort -V. Document it in docs/reference.md § Releases and one line in README.md § Updating. no-agent-alert's next_step story merges after staged-epics-next, which comes after this. Draft PRs #480/#482 also edit next_step: rebase on whichever lands first.

Review fixes (critic, codex): the hold counts an epic file carrying the stage as still on the board whatever its status (status: done included), never through open_item. A present but malformed `stage:` value holds the release and prints why, while a board with no stage: field behaves as today. While the next stage is held, a fix-only change since the last tag is still releasable as a patch: next prints `release v<cur>.<n+1> (patch)`, a patch on the current release line (tag v1.2.0 with stage v1.3.0 held gives v1.2.1), never a fourth version part, so a fix never waits on the next stage. The stage read runs only when release_due is already true, with one git log call, so dash's frame and lead-stop's budget are not slowed when no release is due. status and dash show the same release-held line next prints: dash reads only next_step's first line today (bin/lib/dash.sh:599), so this story also passes the hold through dash's input and renders it.

**Done when:**
- tests/next_test.sh, on the release fixture (plugin.json 1.2.0, tag v1.2.0, a commit outside the board since): an open epic carrying `stage: v1.3.0` gives a first line that is not `release` or `release v1.3.0`, and a line `release-held: v1.3.0, open epics: <its slug>, patches only`.
- With that epic's file deleted in a commit since the tag, next's first line is `release v1.3.0`; with a draft epic carrying `stage: v1.4.0` also on the board, it is still `release v1.3.0`.
- With no epic carrying stage:, the existing release cases still print `release` and no `release-held:` line. The three stage cases go red against the current release arm.
- docs/reference.md § Releases describes `release v<S>`, `release-held:` and the board-outside-the-repo case; doc_check passes.
- A test with a stage epic still on the board at status: done prints no `release v<S>`.
- A test with a malformed stage value holds the release and names the epic; a board with no stage field releases as today.
- A test with a fix-only commit after the tag and the next stage held prints the patch on the current line (v1.2.0 gives `release v1.2.1 (patch)`), which merge --release accepts as MAJOR.MINOR.PATCH.
- A test shows next_step makes no git log call when release_due is false, and status and dash print the release-held line.

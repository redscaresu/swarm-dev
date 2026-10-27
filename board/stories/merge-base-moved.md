---
kind: code
status: ready
epic: merge-holds
depends_on: []
touches: [bin/lib/merge.sh:merge_pr base check, bin/lib/ci_gate.py:behind (new), bin/lib/build.sh:conduct_merge_rule moved-base line, tests/merge_fixture.sh:gh stub compare, tests/epic_briefs_test.sh:moved-base line, docs/reference.md:Merging base-moved check, tests/merge_base_moved_test.sh (new)]
estimate_lines: 200
easy: false
risk: high
---

# swarm.sh merge refuses a story PR whose base gained code commits its head lacks

The v0.28.0 lesson: #527 and #530 each passed CI before #529 landed, and main went red.
- In merge_pr's direct path (no merge queue, story route, not --board or --release), after ci_gate head is green and before gh pr merge, compare the head with the base.
- Refuse when the base has commits the head lacks and any of them changes a path off the board (on_board_paths, merge.sh:796). Board-only commits run no tests, as CI's board-only gate has it. The message: `the base <base> moved past <head:0:7>'s CI (<n> commits it lacks): merge origin/<base> in, push, and merge the new head`.
- A compare it cannot read, or one listing 300 files or more, refuses.
- One ci_gate read (a new `behind` mode beside admin's behind_by read, ci_gate.py:129-136): compare <head>...<base> gives the count and the files. ci_gate.py takes the board prefix from bash, as less-noise's constraint has it.
- Conservative on purpose: GitHub's pull_request CI ran on a merge ref, which may already hold some of those commits. The extra CI run is the price.
- The merge-queue path (queue_merge) is unchanged, since the queue tests the combination. merge_admin = on with a strict base stays ci_gate admin's job.
- tests/merge_fixture.sh's stub answers the new compare with nothing behind by default, so existing merge tests pass.
- The conductor's merge rule (bin/lib/build.sh:conduct_merge_rule, merge = agent arm) gains a line for the new refusal. The conductor nudges the builder to merge origin/<base> in and push, waits with wait-pr, reviews the new head as for any new head, and merges it with --head. Without that line the refusal falls under 'a merge swarm.sh merge refused', which goes to the lead.
- Docs: merge_pr's header comment and docs/reference.md § Merging.
- No depends_on (the lead's call). It shares merge_pr's header comment and § Merging with protected-path-hold: if both are open, protected-path-hold merges first and this rebases.
- The new test file uses small fixtures and stays out of SLOW (Makefile:20-26). If it must join SLOW, this PR edits the Makefile, a protected path, and ci.yml's shard count (tests/test_shard_test.sh), so the PR waits for the user's merge. Say so in the PR.
- Order across epics: conductor-hands-off's story-merge-notes-conductor, fixes-027's epic-guard-story-merge and less-noise's board-root-helper also edit merge.sh:merge_pr. review-loop's merge-from-review-pane edits reference.md § Merging. conductor-hands-off's conduct-brief-hands-off and conductor-report-hold edit build.sh:conduct_merge_rule. If any of them is open alongside this one, it merges first and this one rebases onto it. If conduct-brief-hands-off has already moved merging out of conduct_merge_rule, the brief line goes where the merging agent's rule now lives. Say where in the PR.

**Done when:**
- tests/merge_base_moved_test.sh (new): a story PR is green on its head, and the base then gains a commit changing bin/x.sh. swarm.sh merge refuses with the moved-base message and runs no `pr merge` (gh.log).
- Same file: a base that gained only a board-file commit merges. A head up to date with the base merges. A failed compare refuses and names it. On a base with a merge queue, no compare is read.
- Same file, the v0.28.0 case: PR A merges, then PR B, green on the old base, is refused.
- tests/epic_briefs_test.sh shows the merge = agent conductor brief carrying the moved-base line: nudge the builder to merge origin/<base> in, wait-pr, review the new head, merge with --head.
- The PR body says the moved-base case passed with the check removed in a copy of the checkout, so the test catches the gap.
- tests/merge_test.sh, tests/merge_rules_test.sh and tests/merge_queue_test.sh pass.
- reference.md § Merging describes the check, its board-only exception, the message and what the conductor does.

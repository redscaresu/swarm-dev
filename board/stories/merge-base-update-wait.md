---
kind: code
status: blocked
epic: merge-holds
depends_on: [merge-base-update-branch]
needs: [merge-base-update-branch: merge_base_update in bin/lib/merge.sh (the update and parent check), its `merge <slug> base-merged <new head>` events line and its `base merged:` conductor line, which this story turns into a wait and a merge]
touches: [bin/lib/merge.sh:merge_pr base check, bin/lib/merge.sh:merge_base_update, bin/lib/merge.sh:watch_prs base-merged head, bin/lib/build.sh:conduct_merge_rule moved-base line, docs/reference.md:Merging base-moved check, tests/epic_briefs_test.sh:moved-base line, tests/merge_base_update_test.sh:base merged cases, tests/merge_base_update_wait_test.sh (new)]
estimate_lines: 250
easy: false
risk: high
---

# swarm.sh merge waits for the base-merged head's CI, re-checks the base, then merges it

Uses merge-base-update-branch's update and parent check (bin/lib/merge.sh:merge_base_update), its `base-merged` events line and its `base merged:` conductor line.
- Where merge-base-update-branch ends with `base merged:`, merge_pr instead waits up to MERGE_CI_SECONDS for green on the new head (ci_gate head polled, as merge's own CI wait is).
- Right before gh pr merge it checks the base again. If the base gained more code commits, it repeats the update and the wait. After MERGE_BASE_ROUNDS rounds (a named constant, at most 3) it refuses, naming the rounds. Otherwise it merges with --match-head-commit <new head>.
- It refuses, naming the cause, on a red new head (naming the red checks), on no check runs within MERGE_CI_GRACE, and on a timeout.
- The head moving under others: merge pushed a commit to the builder's branch, so:
  - watch (merge.sh:watch_prs) must not send the base-merged head out as new work. It reads the `base-merged` record and prints no `checks finished on <sha>` line that starts a review for that head.
  - A review agent or conductor that compares heads treats a recorded base-merged head of its reviewed head as reviewed. The conductor's merge rule (bin/lib/build.sh:conduct_merge_rule) says so.
  - The builder's worktree lacks the merge commit. A refusal on the new head (red, timeout, rounds) says the builder pulls its branch (`git pull --ff-only`) before pushing, and the conductor's nudge carries that.
- The conductor's merge rule also says merge can now take up to MERGE_CI_SECONDS longer when the base moved, and must be left to finish.
- Docs: merge_pr's header comment and docs/reference.md § Merging.
- The new test file uses small fixtures and stays out of SLOW (Makefile:20-26). If it must join SLOW, this PR edits the Makefile, a protected path, and ci.yml's shard count (tests/test_shard_test.sh), so the PR waits for the user's merge. Say so in the PR.
- Order across epics: conductor-hands-off's story-merge-notes-conductor, fixes-027's epic-guard-story-merge and less-noise's board-root-helper also edit merge.sh:merge_pr. review-loop's merge-from-review-pane edits reference.md § Merging. conductor-hands-off's conduct-brief-hands-off and conductor-report-hold edit build.sh:conduct_merge_rule. If any of them is open alongside this one, it merges first and this one rebases onto it. If conduct-brief-hands-off has already moved merging out of conduct_merge_rule, the brief line goes where the merging agent's rule now lives. Say where in the PR.
- conductor-hands-off's watch-opened-pr also edits merge.sh:watch_prs: if both are open, it merges first and this rebases.

**Done when:**
- tests/merge_base_update_wait_test.sh (new): with a moved base, merge updates the branch, waits for the new head's green and runs `pr merge --match-head-commit <new head>` (gh.log). events.tsv shows base-merged, then `merge ok`.
- Same file, a second move: the base gains another code commit while the new head's CI runs. merge updates again, waits again, and merges the second new head. With the base moving on every round, it refuses after MERGE_BASE_ROUNDS with no `pr merge`.
- Same file: a red new head, no check runs, and a timeout each refuse, naming the cause, with no `pr merge`. The refusal tells the builder to pull its branch first.
- A watch test: while a base-merged record names the head, `swarm.sh watch` prints no line that sends the PR to review for that head. A builder's own later push is reported as today.
- tests/epic_briefs_test.sh shows the conductor's merge rule saying a base-merged head needs no new review, that merge may run longer, and that a refusal's nudge tells the builder to pull first.
- tests/merge_base_update_test.sh's `base merged:` cases now expect the wait and the merge. Its parent, 422 and no-new-head refusals pass unchanged.
- reference.md § Merging describes the wait, the second check, the rounds limit and what watch, the reviewer and the builder do with the base-merged head.

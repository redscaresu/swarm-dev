---
kind: code
status: blocked
epic: merge-holds
depends_on: [merge-base-moved]
needs: [merge-base-moved: the base check in bin/lib/merge.sh:merge_pr, ci_gate.py's behind mode and its moved-base conductor line, which this story turns into a base merge]
touches: [bin/lib/merge.sh:merge_pr base check, bin/lib/merge.sh:merge_base_update (new), bin/lib/build.sh:conduct_merge_rule moved-base line, docs/reference.md:Merging base-moved check, tests/epic_briefs_test.sh:moved-base line, tests/merge_base_moved_test.sh:moved-base cases, tests/merge_base_update_test.sh (new)]
estimate_lines: 180
easy: false
risk: high
---

# swarm.sh merge merges a moved base into the PR branch and checks the new head's parents

Uses merge-base-moved's base check in bin/lib/merge.sh:merge_pr and its `ci_gate behind` read.
- Where merge-base-moved refuses, merge_pr first asks GitHub to merge the base into the PR branch: `PUT repos/<o>/<r>/pulls/<n>/update-branch` with expected_head_sha set to the pinned head.
- It then reads the PR's head until it changes, within a bound. It accepts the new head only when the first parent is the pinned head and the second is a commit on <base>, so the only new content is the base's.
- The exit stays a refusal: `base merged: <url> is now <new head:0:7> (<pinned head:0:7> with <base> merged in); wait-pr --head <new head>, then merge --head <new head>`. merge-base-update-wait turns that into a wait.
- An events line, `merge <slug> base-merged <new head>`, records the base merge, so later steps can tell this head from a builder's push.
- It refuses, naming the cause, in three more cases: a conflict (HTTP 422), so the builder merges origin/<base> in; a new head with any other parent pair, so review the new head; and no new head within the bound.
- The conductor's merge rule (bin/lib/build.sh:conduct_merge_rule) says a head named in a `base merged:` line needs no new review, since its only new content is the base's. The conductor runs the wait-pr and merge the line names.
- Docs: merge_pr's header comment and docs/reference.md § Merging.
- The new test file uses small fixtures and stays out of SLOW (Makefile:20-26). If it must join SLOW, this PR edits the Makefile, a protected path, and ci.yml's shard count (tests/test_shard_test.sh), so the PR waits for the user's merge. Say so in the PR.
- Order across epics: conductor-hands-off's story-merge-notes-conductor, fixes-027's epic-guard-story-merge and less-noise's board-root-helper also edit merge.sh:merge_pr. review-loop's merge-from-review-pane edits reference.md § Merging. conductor-hands-off's conduct-brief-hands-off and conductor-report-hold edit build.sh:conduct_merge_rule. If any of them is open alongside this one, it merges first and this one rebases onto it. If conduct-brief-hands-off has already moved merging out of conduct_merge_rule, the brief line goes where the merging agent's rule now lives. Say where in the PR.

**Done when:**
- tests/merge_base_update_test.sh (new; the stub serves update-branch, the new head's commit with its parents, and the PR's head after the update): with a moved base, gh.log shows update-branch called with expected_head_sha = the pinned head. merge exits non-zero with the `base merged:` line naming the new head, runs no `pr merge`, and events.tsv has `merge <slug> base-merged <new head>`.
- Same file: a new head whose parents are not (pinned head, base commit) is refused with a line saying so. The same holds for an update-branch 422 (naming the conflict) and for a head that never changes, each with no `pr merge`.
- tests/merge_base_moved_test.sh's moved-base cases now expect the update. Its board-only, up-to-date and queue cases pass unchanged.
- tests/epic_briefs_test.sh shows the conductor's merge rule carrying the `base merged:` line.
- The PR body says the parent-mismatch case passed with the parent check removed in a copy of the checkout.
- reference.md § Merging describes the base merge, the parent check and each refusal.

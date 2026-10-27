---
kind: code
status: ready
epic: shared-helpers
depends_on: []
touches: [bin/lib/board.sh:drop_gone_state, tests/reconcile_pull_test.sh:pulled-away case, tests/pr_removes_story_test.sh:drop case]
estimate_lines: 110
easy: false
risk: high
---

# reconcile finishes a merged story whose file a pull already removed

When the main checkout's pull removes a story file before reconcile sees its PR merged (a pull by hand, or a reconcile that pulled and died), reconcile_board's merged loop (bin/lib/board.sh:1760-1792) never lists it and drop_gone_state (:1852-1869) only state_drops it, so its builder pane and worktree stay. In drop_gone_state, for a story whose build is recorded and whose PR merged (read as the merged loop reads it), run close_agent (bin/lib/lifecycle.sh:475), then clear_build (:1450) unless CLOSE_PANE_KEPT (as :1783-1785), and log `reconcile <slug> ok (finished)`. A story with no merged PR (a drop) only loses its state, as today. review-loop's close-review-after-merge follows this story and tests this path (epic Constraints).

**Done when:**
- tests/reconcile_pull_test.sh gains a case: a story in review whose PR merged and whose file a pull already removed ends with its builder closed, its build cleared and a `reconcile <slug> ok (finished)` event; it fails with the new path removed.
- tests/pr_removes_story_test.sh gains a case: a story dropped by a board PR, with no merged PR, only loses its state.
- A builder whose pane cannot be closed keeps its worktree and branch, in the same test.

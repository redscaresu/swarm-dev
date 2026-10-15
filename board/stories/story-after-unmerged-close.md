---
kind: code
status: ready
touches: [bin/swarm.sh:reconcile, bin/swarm.sh:story, tests/epic_test.sh]
---

# A story whose PR closed unmerged can be built again

When a story's PR is closed unmerged, `reconcile` sets the story back to `ready`, but its worktree and local `story/<slug>` branch stay. The next `swarm.sh story <slug>` then dies at `git worktree add -b` because the branch exists. `reconcile` should remove that worktree and branch (and origin's `story/<slug>` if it is still there) when it readies a story from a closed PR, as long as no builder for the slug is open. `story` should not delete anything itself; with a builder open, reconcile leaves the worktree and says so.

**Done when:**
- tests/epic_test.sh: after a story's PR is closed unmerged (stubbed `gh`) and `reconcile` runs with no builder open, the worktree dir, local `story/<slug>` and origin's `story/<slug>` (seeded in the test's bare origin) are gone, and `story <slug>` succeeds and its builder can push `story/<slug>`.
- With the builder still open, `reconcile` leaves the worktree and branch and prints a line naming the slug.
- The PR shows the new check failing with the cleanup removed; shellcheck and every tests/*_test.sh pass.

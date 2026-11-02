---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/build.sh:stack_start, bin/lib/build.sh:build_story stacked brief line, bin/lib/merge.sh:stacked_parents, bin/lib/merge.sh:stacked_child, docs/reference-building.md:Stacked builds, tests/stacked_test.sh:conflicting parents cases]
estimate_lines: 220
easy: false
---

# A story whose two parents conflict starts stacked on one and takes the other once it merges

HLD telemetry item 5 (HLD:517-518): 6 of 11 holds in the v0.30.0 build were stories whose two parents conflict. stack_start (bin/lib/build.sh:1666-1689) merges each later parent into the first parent's branch; on a conflict it removes the worktree and branch and dies with merge_clash (1685-1690, 1700-1705), and the conductor then holds the story (startable_rule, build.sh:335). Change: abort that merge, keep the worktree on the parents merged so far, and record the left-out parents in the stacked event, e.g. `ok (on <merged>; left <p>: conflicts with <q> in <files>)`. build_story's stacked brief line (build.sh:670) names the left-out parent and says its code arrives through the base once it merges. stacked_parents and stacked_child (bin/lib/merge.sh:3041-3102) read the event: a left-out parent whose PR is open gives no `merge origin/story/<p>` line (that merge conflicts); once it merges, the existing `merge origin/<base> (<p> merged)` line covers it. review still holds the child until every parent merges (held_by, board.sh:2519-2538): unchanged. The parent fetch and open-PR checks stay. tests/stacked_test.sh:180 pins today's failure; it changes. stacked_parents parses the stacked event with a fixed substr (merge.sh:3044): the new event form must parse there, pinned by a test.

**Done when:**
- tests/stacked_test.sh: with two parents that conflict in f.txt, `swarm.sh story <child>` exits 0, the worktree sits on the first parent's branch, the stacked event names the left-out parent, and the brief names it.
- tests/stacked_test.sh: while the left-out parent's PR is open, status prints no `merge origin/story/<p>` line for it; once the stub reads it MERGED, status prints `merge origin/<base> (<p> merged)`.
- tests/stacked_test.sh: with three parents where only the third conflicts, the second is merged in and the third left out.
- tests/stacked_test.sh: stacked_parents reads the new stacked event (with a left-out parent) and status prints the Stacked merge line for the parent that was merged in.
- docs/reference-building.md § Stacked builds says so, and the PR body shows each case red with the change removed.
- After a left-out conflicting parent, the worktree has no unmerged entries, no MERGE_HEAD and a clean status before the builder starts.

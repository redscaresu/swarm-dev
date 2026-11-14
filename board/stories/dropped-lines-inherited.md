---
kind: code
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:merge walk (inherited merges), tests/dropped_lines_test.sh:stacked-parent cases, docs/reference-merging.md:dropped-lines paragraph (§ Merging) inherited sentence]
estimate_lines: 80
easy: true
risk: high
---

# The dropped-lines check skips merge commits inherited from a parent that already merged

On 2026-11-14, swarm.sh merge held #855 (flaky-upgrade-deadline) for 6 dropped lines. All 6 come from e4a7381, a merge of main into its parent's branch. The parent was #829 (upgrade-skip-closed), which #855 was stacked on. #829 removed those lines on purpose and was reviewed and merged with them removed, so main no longer has them and #855 drops nothing. But bin/lib/dropped_lines.py walks every merge in `git rev-list --first-parent --merges <base>..<head>`, and once #829 is squash-merged, its merge commits are still in #855's history and not reachable from main. So the check reports a parent's reviewed change as #855's own drop, and a person has to merge by hand.

Skip a merge commit whose dropped lines are already absent from the base's current version of the file. A line only counts when the base still has it at the PR's merge-base with the base. A merge an already-merged parent made therefore stops counting once the parent's squash is on main. A drop the PR itself makes, of a line main still has, keeps printing. This check is a safety rail, so prove each case on a fixture.

**Done when:**
- tests/dropped_lines_test.sh: a fixture where a parent branch merges main and drops line L on purpose, the parent is squash-merged into main (so main no longer has L), and a child branch stacked on the parent has that merge in its history: the child prints nothing and exits 0
- A fixture where the child's own merge of main drops a line main still has still prints it and exits 1
- Every existing case in tests/dropped_lines_test.sh still passes, including the both-sides case dropped-lines-both-sides added
- The first case goes red with the change removed, and the second stays red with it in, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-merging.md's dropped-lines paragraph says a line the base itself no longer has does not count
- scripts/select-tests.sh --run passes

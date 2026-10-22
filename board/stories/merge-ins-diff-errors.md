---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/flow_merge_ins.py, tests/flow_test.sh]
estimate_lines: 30
easy: true
---

# flow's merge-in causes count a failed git diff as unread, not as an empty diff

Codex flagged a P2 in #346 (main-merge-in-causes, merged) while reviewing another PR. In
bin/lib/flow_merge_ins.py, cause() decides whether a clean-but-different merge-in was hand-fixed by
intersecting `names(git(root, "diff", ..., clean, tree))` and `names(git(root, "diff", ..., base, tree))`.
names() reads only stdout, so a git diff that fails or times out (quiet_git's limit) gives an empty
list, the intersection is empty, and the merge-in falls through to `behind` or `neither` instead of
`unread`. That inflates the very causes the section measures, with no line saying a read failed.

Check both diffs' return codes. When either fails or times out, return `unread` with the error, as
the merge-tree and merge-base paths already do (`f"{oid[:12]}: git diff: {said(...)}"`).

**Done when:**
- A test in tests/flow_test.sh whose stub (or broken object) makes one of the two git diffs fail classifies that merge-in as `unread`, and the left-out line names the git diff error.
- The existing fixture (one conflict, one behind, one neither, one hand-fixed) still classifies as before, and `make test` passes.

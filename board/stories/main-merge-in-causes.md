---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/flow_merges.py, tests/flow_test.sh]
estimate_lines: 120
easy: false
---

# flow breaks main merge-ins down by cause

after-release-checks (2026-10-22): flow's merged-in-main share is 62% (16 of 26 PRs, `flow --since 2026-10-17`) and 63% (17 of 27, `flow --epic safer-faster-swarm`), worse than the 55% baseline this epic set out to lower. The number alone does not say why: a conflict with a sibling story's touches, a stale base before the merge queue, a red main, or a builder merging main in by habit.

For each PR that merged main in, flow classifies the merge-in by what changed: a conflict resolution (the merge commit has conflict markers resolved, or its diff differs from both parents in a file the PR touches), a merge the base asked for (behind with no conflict), or neither. It names the files involved in conflicts. It prints counts per cause and the top three files.

**Done when:**
- A fixture repo with one conflicting merge-in, one clean behind merge-in and one with neither is classified correctly by a test.
- `flow --epic safer-faster-swarm` prints the breakdown (paste it in the PR), and the PR proposes one fix for the largest cause as a new story's title.

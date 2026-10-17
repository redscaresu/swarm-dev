---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/epic_test.sh -> tests/epic_*_test.sh, tests/dash_test.sh -> tests/dash_*_test.sh]
easy: false
estimate_lines: 120
---

# Split epic_test and dash_test by topic so no test file takes over 60 s

Builds on the split. tests/epic_test.sh (1028 lines, 99 s in CI run 38997774775) and tests/dash_test.sh (1129 lines, 86 s) become topic files: epic_layout, epic_briefs, epic_codex, epic_goal and epic_reconcile; dash_layout, dash_needs_you, dash_epics, dash_speedometer and dash_recent. Each keeps its own mktemp root and trap as now (epic_test.sh:8-14), and shared setup is copied, with no new helper. Test bodies move unchanged; the 2150 or so moved lines are not in the estimate, as with the split. A file still over 60 s locally is split again.

**Done when:**
- Every tests/*_test.sh passes, and the PR body shows the assertion count across the new files equals the old two files'.
- Local timed runs quoted in the PR body show no tests/*_test.sh over 60 s.

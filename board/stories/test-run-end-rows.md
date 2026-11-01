---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [scripts/test.sh:log_run, scripts/test.sh:others, scripts/test.sh:cleanup trap, tests/test_runs_log_test.sh (new), docs/reference-logs.md:test_runs section (test-runs.tsv), docs/running.md:Test tooling (test-runs.tsv line)]
estimate_lines: 140
easy: false
---

# Explain and close the gap in test-runs.tsv end rows

Of 1186 start rows in .swarm/test-runs.tsv, 218 have no end row (156 of 252 full-suite starts; read 2026-11-01). Only cleanup on the EXIT trap writes an end row (scripts/test.sh:363-382); the start row is written before that trap is set (test.sh:355 vs 382), and ends with status 143/130 exist (66 and 19), so TERM and INT already log. Likely cause SIGKILL, unproven. Find the cause by reproduction, set the trap before the start row, and have a later run write an end row for a run that died with no end row: its mark in .swarm/test-runs.d (others(), test.sh:340-348) holds its start time, is claimed by rename, and gets one end row with status 137. flow_test_runs.py is unchanged: it already skips status >= 128.

**Done when:**
- The PR names which signals left a start row with no end row before the fix, from a reproduction in the test (TERM, INT, HUP, PIPE and KILL sent after the start row), and the counts above from test-runs.tsv read once.
- A new test sends TERM between the start row and the first job and finds the run's end row; it goes red with the trap moved back after the start row.
- A new test SIGKILLs a run after its start row, starts another run, and finds exactly one end row for the killed run (its start and PID, status 137); it goes red with the sweep removed.
- make test still passes; docs/running.md and docs/reference-logs.md's test_runs paragraph say what a status-137 end row means.
- Two successor runs started together against one stale start row write exactly one recovered end row between them.

---
kind: code
status: blocked
epic: machine-usable
depends_on: [test-run-end-rows]
needs: [test-run-end-rows (its edit of docs/reference-logs.md's test_runs paragraph merged first (same part).)]
touches: [bin/lib/flow_test_runs.py:timeouts column, tests/flow_test_runs_test.sh:timeouts cases, docs/reference-logs.md:test_runs section (timeouts), docs/reference-logs.md:Commands (flow row section list, 909), bin/lib/reports.sh:flow comment (test_runs columns, 440-447)]
estimate_lines: 60
easy: true
---

# flow test_runs counts test-file timeouts

Builds on test-run-end-rows' text in the test_runs paragraph of docs/reference-logs.md. No flow section reads reap lines today. flow_test_runs.py (it reads only test-runs.tsv, :15-44) gains a `timeouts` column: the reap lines scripts/test.sh writes to events.tsv (outcome `TIMEOUT after <n>s`, test.sh:111-115) whose local day is in the window; codex reaps (reference-logs.md:84-91) are not counted. It is a count over the window: the HLD's bar 'under 100 per build (2,050)' is per release build, so it is read over one release's window, with no per-story divisor. The section prints its header and a 0 timeouts column with no test-runs.tsv, so features_test.sh can see it.

**Done when:**
- tests/flow_test_runs_test.sh: fixtures with 3 test.sh reap lines in the window, 1 outside it and 1 codex reap give timeouts 3; it goes red with the reap read removed.
- With no test-runs.tsv and no reap line the section prints its header and timeouts 0; with no test-runs.tsv but reap lines in events.tsv it counts them.
- With no reap line in the window the column says 0, and the paragraph says what 0 means (rules.md rule 6).
- docs/reference-logs.md's test_runs paragraph names the column.

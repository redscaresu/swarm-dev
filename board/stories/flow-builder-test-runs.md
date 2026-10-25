---
kind: code
status: ready
epic: test-speed
depends_on: []
touches: [bin/lib/flow_test_runs.py, tests/flow_test_runs_test.sh, bin/lib/reports.sh:flow_report test_runs comment, docs/reference.md:test_runs section, docs/reference.md:test_runs words in the flow row, docs/features.tsv:test-selection row, README.md:test-runs.tsv line in More]
estimate_lines: 95
easy: true
---

# flow's test_runs reports builder runs of every filter, with median and p90

bin/lib/flow_test_runs.py keeps only `all` end lines (:28). Keep that at_once table and the slowest list as the baseline, unchanged. Add a block for builder runs: end lines whose branch (field 6) starts with `story/` (bin/lib/build.sh:524), of every filter, `all` fallbacks included, less interrupted (status 128 or more) and torn lines, by start's local day in the window. It gives runs, median and p90 seconds (nearest rank, as :48). No run-mark format change (scripts/test.sh:155-160; epic Out of scope). Update the header comment (:1-10), flow_report's comment (bin/lib/reports.sh:385-389), reference.md's test_runs section (:1438-1455), the test_runs words in the flow row (:2015), and README.md:166's test-runs.tsv line (flow output is user-visible). tests/flow_test_runs_test.sh pins the old exclusions (:107-134): update it. Add a docs/features.tsv row: feature test-selection, landed test-speed, metric `flow test_runs: builder p90 s`, baseline `0.27: median 1050 s, p90 1391 s over the 17 of 35 full runs with no other run going (HLD Appendix A); bar p90 300 s`, uses `unlogged: ...`. stage-gating's release stories quote that metric and bar (board/epics/stage-gating.md:23), so keep the strings exact.

**Done when:**
- tests/flow_test_runs_test.sh pins, on a fixture: a story/* run with a TESTS filter, a story/* `N files` run and a story/* full run count in the builder block with the expected median and p90; a run on main or `-`, a shard run, an interrupted run and a torn line do not; the at_once table still counts only `all` runs.
- docs/features.tsv has the test-selection row with metric `flow test_runs: builder p90 s` and the 300 s bar; features_test and doc_check_test pass.

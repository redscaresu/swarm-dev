---
kind: code
status: ready
epic: report-speed
depends_on: []
touches: [bin/swarm.sh:status, next and dash dispatch arms, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/flow_run_times.py (new), tests/flow_run_times_test.sh (new), docs/reference.md:run-times log row, docs/reference.md:Flow and features section list, docs/reference.md:flow command row]
estimate_lines: 160
easy: false
---

# flow reports how long status, next and dash took

READ_ONLY_COMMANDS are not logged to events.tsv (bin/swarm.sh:583-588), and stay so. The status, next and dash dispatch arms write one row per run to their own file, .swarm/run-times.tsv: time, command, seconds, 1-minute load average (dash --watch: its first frame only). Nothing else writes there: no _step, no wait --lead poll. Update the READ_ONLY_COMMANDS comment to name this file among the lines read-only commands write. Add a flow section in bin/lib/flow_run_times.py (new; flow runs one section per flow_<name>.py): per command, runs, median and p90 seconds and the share over 60 s in the window. Document the log in docs/reference.md's logs list and the section in Flow and features and the flow command row.

**Done when:**
- tests/flow_run_times_test.sh (new): status, next and dash in a fixture project each leave one run-times.tsv row and no events.tsv line; `_step` and `wait --lead 0` leave no row; a fixture log gives the expected median and p90 per command. Each check fails with the row, the section, or an events.tsv line added.
- tests/doc_check_test.sh and tests/live_logs_test.sh pass.

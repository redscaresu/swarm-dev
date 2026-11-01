---
kind: code
status: ready
epic: status-speed
depends_on: []
touches: [bin/lib/flow_run_times.py:by-load block, tests/flow_run_times_test.sh:by-load cases, docs/reference-logs.md:run_times paragraph (§ Flow and features, 829), docs/running.md:run-times line (§ Test tooling, 180), bin/lib/reports.sh:run_times comment lines (426-428), docs/reference-logs.md:Commands (flow row section list, run_times)]
estimate_lines: 70
easy: true
---

# flow's run_times gives each command's median per load band

flow_run_times.py gives one median per command over every row, but status's time follows machine load. In .swarm/run-times.tsv (2026-10-28 to 2026-11-01), status's median is 103 s at a 1-minute load under 10, 279 s at 10-20 and 1123 s at 20 and over (survey). Without the load, the epic's 'median under 30 s' cannot be judged. After the existing table, add a blank line, then a by-load block: TSV `command load runs median_s`, one row per command and load band (<10, 10-20, 20+, and - for a row whose load is -). Rows go in command-name order, then band order. The band edges are named constants. The first table is unchanged. Leave the flow row in docs/reference-logs.md § Commands (923) alone: it names the section in brief, and flow-panes and flow-test-runs-timeouts both edit that line.

**Done when:**
- tests/flow_run_times_test.sh: a fixture log with status runs at loads 4, 12, 25 and - prints the by-load block with one row per band and its runs and median; the first table's rows are the same as today's on that fixture.
- Same file: with the band split removed (every row in one band), the test goes red.
- flow_sections_test.sh passes unchanged.
- docs/reference-logs.md's run_times paragraph, docs/running.md's run-times line and reports.sh's run_times comment name the by-load block.
- docs/reference-logs.md's flow row in Commands names the by-load block.

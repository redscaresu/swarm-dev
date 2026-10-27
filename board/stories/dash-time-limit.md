---
kind: code
status: blocked
epic: report-speed
depends_on: [report-deadline, idle-lines-in-lead-queue]
needs: [report-deadline: report_read and report_skipped (bin/lib/merge.sh), idle-lines-in-lead-queue: dash_render as it leaves it (shared part)]
touches: [bin/lib/dash.sh:dash, bin/lib/dash.sh:dash_render, bin/lib/dash.sh:dash_watch, tests/dash_time_limit_test.sh (new), docs/reference.md:dash command row]
estimate_lines: 120
easy: false
---

# swarm.sh dash finishes within the report deadline, and dash --watch draws at once

Uses report-deadline's report_read and report_skipped, and dash_render as idle-lines-in-lead-queue leaves it (shared part). dash (bin/lib/dash.sh:12) and dash_render (:578) run their blocking reads through report_read and show report_skipped's line; dash --watch (dash_watch :425) draws its first frame from what it has within the deadline. dash --check still compares like with like.

**Done when:**
- tests/dash_time_limit_test.sh (new): with reads sleeping past the limit, dash exits within the limit plus a few seconds and names the skipped reads, and dash --watch's first frame appears within it. Each fails with report_read taken out.
- tests/dash_test.sh and the dash --check test pass.

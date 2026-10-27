---
kind: code
status: ready
epic: report-speed
depends_on: []
touches: [bin/lib/merge.sh:report_read (new), tests/report_deadline_test.sh (new)]
estimate_lines: 80
easy: true
---

# A deadline helper for reads in status, next and dash

At load 14 to 18 in v0.28.0, status, next and dash each took 1 to 3 minutes, the lead's 2-minute checks timed out, and dash --watch sat blank for about a minute (v0.28.0 retro). Add report_read (bin/lib/merge.sh, beside within :926-937): REPORT_SECONDS, a constant and no setting, starts when a report starts; report_read <name> <command>... runs a read that can block (a herdr list or read, a gh call, a git fetch) under `within` with the time left, and on a cut-off records <name>; report_skipped prints `skipped (over <n> s): <names>`. It only ever runs reads: no write and no agent start goes through it. The adoption is one story per report: status-time-limit, next-time-limit, dash-time-limit.

**Done when:**
- tests/report_deadline_test.sh (new): a read that finishes in time returns its output and status; one that sleeps past the time left is cut within a second of it and named by report_skipped; a second read after the deadline is skipped at once. Each fails with the deadline removed.

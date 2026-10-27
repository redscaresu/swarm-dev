---
kind: code
status: blocked
epic: report-speed
depends_on: [report-deadline, idle-lines-in-lead-queue]
needs: [report-deadline: report_read and report_skipped (bin/lib/merge.sh), idle-lines-in-lead-queue: status_report as it leaves it (shared part)]
touches: [bin/lib/merge.sh:status_report, tests/status_time_limit_test.sh (new), docs/reference.md:status command row]
estimate_lines: 80
easy: true
---

# swarm.sh status finishes within the report deadline

Uses report-deadline's report_read and report_skipped, and status_report as idle-lines-in-lead-queue leaves it (shared part). status_report (bin/lib/merge.sh:1817+) runs each blocking read through report_read and prints report_skipped's line last; its output with fast reads is as before. Find which reads dominate first and say in the PR. docs/reference.md's status row says what a skipped read looks like.

**Done when:**
- tests/status_time_limit_test.sh (new) with herdr and gh stubs that sleep past the limit: status exits within the limit plus a few seconds and names the reads it skipped; with fast stubs its output is unchanged. It fails with report_read taken out.

---
kind: code
status: blocked
epic: report-speed
depends_on: [report-deadline]
needs: [report-deadline: report_read and report_skipped (bin/lib/merge.sh)]
touches: [bin/lib/board.sh:next_report, tests/next_time_limit_test.sh (new), docs/reference.md:next command row]
estimate_lines: 120
easy: false
risk: high
---

# swarm.sh next finishes within the report deadline, and never cuts a conductor start

Uses report-deadline's report_read and report_skipped. next_report (bin/lib/board.sh:447+) runs its blocking reads (conductors_queued's gh calls, herdr lists) through report_read and prints report_skipped's line after the step. next also starts conductors (conduct_ready, bin/lib/merge.sh:444-492): every write (events.tsv, state, briefs) and every conductor start stays outside the deadline and runs to its end; only reads are cut. The step line stays first (next | head -1 callers), and hooks/lead-stop.sh's `_step` path is unchanged.

**Done when:**
- tests/next_time_limit_test.sh (new): with gh and herdr reads sleeping past the limit, next exits within the limit plus a few seconds, prints its step first and names the skipped reads; a conductor start slower than the limit still completes and logs its conduct line. Each fails with report_read taken out, or with the start put under the deadline.
- tests/next_test.sh passes.

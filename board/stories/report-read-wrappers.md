---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/merge.sh:report_wrappers (new, beside report_read), bin/lib/merge.sh:status_reads, bin/lib/board.sh:next_reads, bin/lib/dash.sh:dash_deadline, tests/report_deadline_test.sh:wrapper names case (new), docs/dash.md:skipped line example (only if the name changes)]
estimate_lines: 120
easy: false
---

# status, next and dash share one set of report_read wrappers

#700 item 11 (#630). The herdr, claude and gh wrappers that run reads under the report deadline are written three times: dash_deadline (bin/lib/dash.sh:100-109), status_reads (merge.sh:3302 on origin/main, after #825, which also wraps git) and next_reads (board.sh:676-688, which also answers herdr agent list from LEAD_AGENTS). The copies have drifted: next names a gh read 'gh api <path>' (${*:1:2}) where status and dash say 'gh api', and next and status take claude's $1 bare under set -u where dash takes ${1:-}. Add one helper beside report_read that defines the three, and have each caller use it and add its own extra (status's git arm, next's agent-list answer, next_reads off). Pick one naming for a skipped read and say it in any doc that quotes a skip name (docs/dash.md:18 and the status/next rows if they do). Tests in tests/report_deadline_test.sh. Prove the new case fails with next_reads' own copy restored, on a worktree copy. dash's gh reads are python's (dash.sh:107), so test the shared helper's names directly, or name a real dash frame read that goes through a shell `gh api` call.

**Done when:**
- tests/report_deadline_test.sh: the shared helper names a slow `gh api` read the same way for status, next and dash (exercising each caller's installed wrappers)
- That case goes red with next_reads' own gh wrapper restored, shown on a worktree copy
- tests/dash_time_limit_test.sh, tests/status_time_limit_test.sh and the next tests pass
- scripts/select-tests.sh --run passes
- Restoring status's or dash's own wrapper copy turns the case red too; a mutation each.

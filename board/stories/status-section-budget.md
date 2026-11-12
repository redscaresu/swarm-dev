---
kind: code
status: blocked
epic: status-speed
depends_on: [status-section-times, report-board-snapshot, report-epic-walks]
needs: [status-section-times (status_report's section boundaries (its timers) and its docs/running.md status row edit), report-board-snapshot (its docs/reference-building.md status row edit), report-epic-walks (the faster epic walks; so the section times the budget is set from are current)]
touches: [bin/lib/merge.sh:status_report (section deadline checks), tests/status_section_budget_test.sh (new), tests/status_time_limit_test.sh:slow-stub expectations, docs/reference-building.md:status row (§ Commands, 1104), docs/running.md:status row (§ Watching a run, 69)]
estimate_lines: 120
easy: false
---

# status skips a section due past its deadline and names it

Needs from status-section-times: the section boundaries in status_report where its timers sit, and its edit of docs/running.md's status row. Needs from report-board-snapshot: its edit of docs/reference-building.md's status row. REPORT_SECONDS bounds only reads (report_read, merge.sh:2088); local work runs on past it. Before each section after Agents (Stacked, Waiting on you, Next with its idle lines), status checks REPORT_END. A section due at or past it is not run. Its heading says `skipped (over N s)`, and its name goes into REPORT_SKIP_FILE after the reads already cut, so report_skipped's last line keeps the `skipped (over N s): ` prefix that status_time_limit_test.sh:120-125 matches. A section already running finishes. next is not cut (see contradictions). dash --check's status run keeps its day-long deadline (dash.sh:388), so it is never cut. There is no new setting: the budget is REPORT_SECONDS. A section already running finishes, so the whole run is bounded by the deadline plus its slowest section: the Done when checks that bound, not only the skipped headings.

**Done when:**
- tests/status_section_budget_test.sh: with SWARM_REPORT_SECONDS=1 and a herdr stub whose pane list sleeps past it, status prints the Stacked, Waiting on you and Next headings with `skipped (over 1 s)` and no rows under them; a stub gh that logs calls logs none after the cut; the last line is `skipped (over 1 s): ` naming the cut herdr read first, then the sections.
- Same file: with one section's stub sleeping 3 s and SWARM_REPORT_SECONDS=1, the whole status run ends within the deadline plus that one section (under 5 s).
- Same file: with fast stubs and a one-hour deadline, status prints every section's rows and no skipped line.
- Same file: with the deadline check removed (proved on a worktree copy), the slow run prints Waiting on you's rows and the test goes red.
- status_time_limit_test.sh, report_deadline_test.sh and dash_check_test.sh pass; any expectation the cut changes is updated and listed in the PR.
- docs/reference-building.md's and docs/running.md's status rows say a section due past the deadline is skipped and named on the last line.

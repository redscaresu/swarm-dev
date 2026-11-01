---
kind: code
status: blocked
epic: status-speed
depends_on: [report-board-snapshot, status-section-times]
needs: [report-board-snapshot (board_snapshot and fm's snapshot lookup (the index is built with it); and tests/report_snapshot_test.sh's exec-count fixture; which this extends), status-section-times (SWARM_REPORT_TIMES=1 per-section times for the before and after numbers)]
touches: [bin/lib/board.sh:epic_stories (index lookup), bin/lib/board.sh:board_snapshot (story-to-epic index), bin/lib/board.sh:waiting_on_user (basename), bin/lib/board.sh:next_step (basename), bin/lib/board.sh:idle_epic_lines (basename), bin/lib/board.sh:epic_has_stories (basename), bin/lib/board.sh:epic_after_only (basename), tests/report_snapshot_test.sh:epic walk cases]
estimate_lines: 150
easy: false
---

# A report walks the stories once, not once per epic

Needs from report-board-snapshot: board_snapshot, fm's lookup in it, and tests/report_snapshot_test.sh's exec-count fixture. Needs from status-section-times: SWARM_REPORT_TIMES=1's per-section times. epic_stories (board.sh:119) runs fm and after_story on every story on each call. It has 14 call sites in board.sh, several of them per epic per report: epic_has_stories, epic_after_only via open_item, idle_epic_lines, plannable_epic. So one report costs epics x stories reads. During a report, epic_stories answers from a story-to-epic index built with the snapshot, keeping after_story's rule and board order. The report loops (waiting_on_user, next_step, idle_epic_lines, epic_has_stories, epic_after_only) name an item with ${f##*/} and ${s%.md}, not $(basename): that is one exec per item per loop. With no report, nothing changes.

**Done when:**
- tests/report_snapshot_test.sh: during one status on fixture boards of 20 stories with 5 epics and 60 stories with 15 epics, the basename, sed, awk and head runs grow per added story by at most a bound set below report-board-snapshot's; the PR quotes both counts; with epic_stories' index lookup removed the test goes red.
- Same file: epic_stories gives the same stories in the same order for every epic of the fixture with and without a snapshot, including an after: lead story and a story with no epic.
- Same file: a state_set of epic: or kind: during a report drops the story-to-epic index, and the next lookup reads the new value.
- status_time_limit_test.sh, next_test.sh, dash_golden_test.sh and dash_check_test.sh pass unchanged.
- The PR quotes SWARM_REPORT_TIMES=1 section times for one status on the 60-story fixture, on main and on the branch in one session, each with its 1-minute load.

---
kind: code
status: ready
epic: status-speed
depends_on: []
touches: [bin/lib/board.sh:fm (snapshot lookup), bin/lib/board.sh:get_fm_or_gone (snapshot lookup), bin/lib/board.sh:board_snapshot (new), bin/lib/board.sh:state_set (snapshot drop), bin/lib/merge.sh:report_start (take the snapshot), tests/report_snapshot_test.sh (new), docs/reference-building.md:status row (§ Commands, 1104), docs/reference-building.md:next row (§ Commands, 1105), docs/dash.md:frame reads paragraph (12-24)]
estimate_lines: 230
easy: false
---

# status, next and dash read the board's front matter once per run

This is the shared cause (rules.md:3). fm and get_fm start sed|head or awk on every call (bin/lib/board.sh:6-9, 2495-2503). The report loops call them per story, per epic and per epic x story: epic_stories board.sh:119, waiting_on_user :2040, next_step :320, idle_epic_lines. Status's median is 103 s even at load under 10 (survey, run-times.tsv), while REPORT_SECONDS bounds only reads (merge.sh:2088-2110). report_start (merge.sh:2073: status, next and each dash frame) takes one snapshot, board_snapshot (new): one awk over board/{stories,epics,hld}/*.md and their BOARD_STATE_DIR state files. Per file it records each key's first line anywhere (fm's rule) and its front-matter value (get_fm's rule), with state values applied by state_read's @base rule (board.sh:66-86). While the snapshot is set, fm and get_fm_or_gone answer from it by parameter expansion, with no exec (bash 3.2 has no associative arrays). A file not in the snapshot is read as today. So is a file now gone: a builtin -e test, so nothing extra is started. Every read after a board-state write in the same run (state_set) sees the write, even a write made in a $( ) subshell; the PR names how. With no report (wait --lead, merge, reconcile, builds), nothing changes.

**Done when:**
- tests/report_snapshot_test.sh: on a fixture board with state files (a key set in state, a @base the item no longer matches, a key only in a story's body, an empty value), fm and get_fm give the same value for every key of every story, epic and HLD file with the snapshot as without it; with the @base check removed from the snapshot the test goes red.
- Same file: during one `status` (outside herdr) on fixture boards of 20 and 60 stories, the sed, awk and head runs (counted by a PATH wrapper) grow per added story by at most a bound set below main's growth on the same fixture; the PR quotes both counts; with the snapshot lookup removed from fm the test goes red.
- The PR quotes one timed status on the 60-story fixture before and after, in one session with its 1-minute load; the after run is not slower.
- Same file: a state_set made in a $( ) subshell during a report is seen by the next fm in the parent shell, and a story file made after the snapshot is read from disk.
- status_time_limit_test.sh, next_test.sh, next_time_limit_test.sh, dash_golden_test.sh, dash_check_test.sh, no_agent_test.sh and stacked_status_test.sh pass unchanged.
- docs/reference-building.md's status and next rows, and docs/dash.md's frame paragraph, say each run (each dash frame) reads the board's files once at its start, so an edit made during the run shows on the next run.

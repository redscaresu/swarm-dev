---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/dash_slow.py:gh, bin/lib/dash.sh:dash (skip file cleanup), bin/lib/dash.sh:dash_watch (EXIT trap), tests/dash_time_limit_test.sh:frame leftover cases (new), bin/lib/merge.sh:report_start (skip file cleanup)]
estimate_lines: 80
easy: true
---

# A dash frame cut short leaves no gh process and no skip file behind

#700 items 9 and 10 (#630). (9) dash_slow.py's gh() (bin/lib/dash_slow.py:32-44) starts gh in a new session and kills that group on its own timeout, a second before DASH_READ_END. When python misses that margin, report_read's within (merge.sh) KILLs python's group at the deadline, and the gh child, in its own session, survives the frame. Run gh in python's group (no start_new_session; kill the child on its own timeout) so the deadline's group kill reaches it. Leave the detached ci refresh (:87, :139) in its own session: it is meant to outlive the frame. (10) The skip file (TMPDIR/swarm-report.<pid>.<end>, merge.sh report_start/report_skipped) stays when dash is killed or stopped mid-frame: remove it on exit, in dash's entry (dash.sh:dash) and dash_watch's EXIT trap (:489-492). Do not edit dash_deadline: report-read-wrappers does. Tests in tests/dash_time_limit_test.sh beside the GH_PIDS check (:84-97). Prove each case fails with its fix removed, on a worktree copy. Item 10 is not dash's alone: status and next use the same report_start (merge.sh:2114) with no trap and leave the same swarm-report.* file when killed. Clean it on exit in all three, through report_start or one trap they share. report-board-snapshot (status-speed) also edits report_start: start from its merged code if it has merged.

**Done when:**
- tests/dash_time_limit_test.sh: with dash_slow.py made to miss its margin (DASH_READ_END past the frame's deadline, or python held), no logged gh pid is alive once dash exits
- A case kills dash --watch (TERM) while a frame has a skip recorded, and no swarm-report.* file is left in the test's TMPDIR
- Killing status and next mid-run (TERM) leaves no swarm-report.* file either; a check each.
- Each case goes red with its fix removed (start_new_session restored; the cleanup removed), shown on a worktree copy
- scripts/select-tests.sh --run passes

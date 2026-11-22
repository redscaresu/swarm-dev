---
kind: code
status: later
epic: helpers-dropped-lines
depends_on: []
touches: [bin/swarm.sh:_dropped-lines arm, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/dropped_lines.py:USAGE, tests/dropped_lines_test.sh:header, DL, scan and the stand-in project, tests/dropped_lines_test.sh:usage checks, tests/events_test.sh:RO_EXPECTED, tests/diff_fixtures_dropped_entry.sh, scripts/allow/stage-2/dropped-lines-entry.md]
estimate_lines: 230
risk: high
---

# swarm.sh _dropped-lines runs dropped_lines.py, and its tests drive that entry

port: true, still on the Python. It adds the seam P3 asks for, so the switch changes only what answers it. bin/swarm.sh's dispatch gains a read-only arm _dropped-lines that runs python3 bin/lib/dropped_lines.py with its arguments and exits with its code; READ_ONLY_COMMANDS (bin/swarm.sh:810) and RO_EXPECTED (tests/events_test.sh:181) gain the name. merge.sh is not edited: dropped-go-switch points its call at the binary (P3). The helper's usage line becomes exactly `usage: swarm.sh _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>]... [<merge sha>...]` (dropped_lines.py:375); dropped-go-scan prints the same text. tests/dropped_lines_test.sh: scan() runs swarm.sh _dropped-lines with SWARM_PROJECT naming a stand-in project made at the top of the file; DL goes; the header and scan()'s comment (lines 2,13,29) name the check, not the file; the two usage checks (284,548) expect the new line. Every other scan() check keeps its arguments and lines, so after the switch all of them reach the Go with the file unchanged. A new file tests/diff_fixtures_dropped_entry.sh (its own file, so pins' edits of diff_fixtures_dropped.sh never clash) has fx_dropped_entry_usage (no arguments: the usage line, exit 2) and fx_dropped_entry_scan (a merge that drops a base line: its line, exit 1), built with diff_fixtures_dropped.sh's helpers, which diff_run.sh sources too (tests/diff_run.sh:208-211). The base tree has no arm, so both fixtures print the dispatch's help text there (bin/swarm.sh:796); scripts/allow/stage-2/dropped-lines-entry.md gives those hunks as --draft prints them (P14). The PR body has a table: each scan() check, the mutation of bin/lib/dropped_lines.py that turns it red (one mutation may cover several checks) and its FAIL line; a check no mutation turns red is named with why. dropped-go-switch repeats the table on the Go. Name and form follow first-port's pattern where it set one.

**Done when:**
- (1) Every check in tests/dropped_lines_test.sh passes with scan() running swarm.sh _dropped-lines, and the file names no bin/lib file outside comments. (2) tests/events_test.sh passes, and goes red on a worktree copy with _dropped-lines taken out of READ_ONLY_COMMANDS. (3) The PR body's table covers every scan() check, each turned red on a worktree copy without .git by a named mutation, with its FAIL line. Its mutations include: owed() always the sum; gone() always False; missing() ignoring the head; extends() always False; every removed line taken as OUTSIDE; MERGED ignored in sides(); a hunk header with no count taken as 0; the arm dropping its last argument. (4) The diff-run job is clean on the PR, applying scripts/allow/stage-2/dropped-lines-entry.md, whose hunks name only fx_dropped_entry_usage and fx_dropped_entry_scan. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

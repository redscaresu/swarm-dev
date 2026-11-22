---
kind: code
status: later
epic: helpers-shared
depends_on: [go-report-logs, go-entries-per-file, shared-copies-list]
needs: go-report-logs: report.SessionLog. go-entries-per-file: the register call. shared-copies-list: docs/port/copies.tsv's archive_session row, deleted here.
touches: [cmd/swarm/session_log.go, bin/ported/_session-log, bin/lib/lifecycle.sh:archive_session, docs/port/sites.tsv:archive_session row, docs/port/copies.tsv:archive_session row, tests/diff_fixtures_archive.sh, tests/nopy_list.txt:fx_archive_session line, tests/lib_path_test.sh:_archive check, tests/speed_list.txt:archive_session line]
estimate_lines: 160
---

# archive_session finds the session log through the binary

Needs SessionLog from go-report-logs, register from go-entries-per-file, and archive_session's row in docs/port/copies.tsv from shared-copies-list. The _session-log entry prints SessionLog(projects, session) as the inline program at bin/lib/lifecycle.sh:486 prints session_log's answer. archive_session calls it with binary_run and keeps its `2>/dev/null || true`. The call sits in a $(...) (bin/lib/lifecycle.sh:486), so with no binary the die ends only that subshell and nothing is archived, as a failed python3 leaves it today. Delete the site's rows in docs/port/sites.tsv (:24) and docs/port/copies.tsv. tests/lib_path_test.sh's _archive check (:32-33) says the copy goes through the binary, not report.py; its shadow-module check stays for helpers-panes to retire. Marker bin/ported/_session-log.

**Done when:**
- (1) tests/diff_run.sh --base <base> is clean on fixtures in tests/diff_fixtures_archive.sh that run `swarm.sh _archive <name>`: a session under projects, one only in the archive (nothing copied), a projects folder named with [ and *, an agent with no session; the source's mtime is fixed so the gz copies compare. tests/speed_list.txt names fx_archive_session. (2) tests/nopy_list.txt gains fx_archive_session with python3, and tests/nopy_test.sh passes. (3) The run goes red with SessionLog's literal folder broken, shown on a worktree copy without .git. (4) tests/port_sites_test.sh passes with archive_session's row deleted. (5) A check in tests/lib_path_test.sh runs `swarm.sh _archive <name>` with SWARMDEV_BIN naming a missing file: it exits 0 and copies nothing. (6) tests/lib_path_test.sh, tests/cost_test.sh, tests/outcomes_test.sh and tests/port_copies_test.sh pass. (7) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

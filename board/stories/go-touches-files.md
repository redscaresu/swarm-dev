---
kind: code
status: later
epic: helpers-shared
depends_on: [go-touches-text, go-store-files, go-events-outcome, go-py-decode]
needs: go-touches-text: touchesrows.FrontText and Pairs. go-store-files: Store.ReadFile and IsFile. go-events-outcome: eventsoutcome.Outcome. go-py-decode: pytext.DecodeReplace.
touches: [internal/touchesrows/files.go, internal/touchesrows/files_compare_test.go]
estimate_lines: 240
---

# touches_rows' file readers run as Go: front with its state file, entries and ok_events

Needs FrontText and Pairs from go-touches-text, ReadFile and IsFile from go-store-files, Outcome from go-events-outcome, and DecodeReplace from go-py-decode. internal/touchesrows: Front(path, stateDir), where the state file's values win unless its <key>@base no longer matches the file, values compared and then trimmed (touches_rows.py:24-33). Entries(fm, projectDir, reposDir): commas split outside parentheses, a repo: prefix, and a part with no / or . that is no file in its repo's checkout belongs to the entry before (:35-64). OkEvents: ok lines by command and target, seconds plus the line's place over the line count (:90-103). stateDir is a required argument, since front() without one reads a global only __main__ sets (:27). A comparison test runs the Python and the Go over the same board and events fixtures, byte for byte: a state file with and without @base, CRLF, non-UTF-8 bytes, parentheses in touches, a repo prefix, Makefile:lint with Makefile present and absent, events with tails, bad times and two lines in one second, plus the inputs tests/events_tail_flow_test.sh gives ok_events (tailed rows) and the state files tests/board_state_test.sh writes (a later commit to a key wins over its state line).

**Done when:**
- (1) The comparison test passes. (2) It goes red when Front alone lets the state win over a changed @base, when Entries alone skips the file check, and when touches_rows.py's ok_events alone drops the line fraction, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

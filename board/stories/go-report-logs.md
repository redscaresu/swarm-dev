---
kind: code
status: later
epic: helpers-shared
depends_on: [go-store-files, go-py-json, go-py-decode]
needs: go-store-files: Store.Glob and ReadFile. go-py-json: pyjson.Decode. go-py-decode: pytext.DecodeIgnore.
touches: [internal/report/logs.go, internal/report/logs_compare_test.go, internal/layers/imports_test.go:allowedStd]
estimate_lines: 270
---

# report's session log readers run as Go: prices, session_log, log_lines, turns and session_usage

Needs Glob and ReadFile from go-store-files, Decode from go-py-json and DecodeIgnore from go-py-decode. internal/report, as bin/lib/report.py:5,41-95 has it: Prices too, since turns is its one user in report.py (outcomes_rows.py:68 and usage_estimate.py:28 import it as well, for their own ports). SessionLog(projects, session, archive): '' for '' or '-'; projects/*/<session>.jsonl, then archive/*-<session>.jsonl.gz; folders taken literally. LogLines: gz or plain, bad bytes dropped as errors="ignore" drops them, nothing for a truncated or non-gzip .gz. Turns: each message id once; a line skipped when its usage is no object, a token is no number or the model is no string (Python counts true as a number). SessionUsage. compress/gzip goes on allowedStd (internal/layers/imports_test.go:16-21). helpers-panes needs SessionLog (board/epics/helpers-panes.md:23). A comparison test runs report.py and the Go over the same projects and archive folders, byte for byte, dollar amounts printed to fixed places on both sides: a folder named with [ and *, an archive-only session, a truncated gz, a .gz holding plain text, duplicate ids, a bool token, an unknown model, and tests/cost_test.sh's logs (a message id logged twice, two models).

**Done when:**
- (1) The comparison test passes. (2) It goes red when SessionLog alone stops taking the folder literally, when Turns alone counts an id twice, and when report.py's turns alone counts an id twice, each shown on a worktree copy without .git. (3) internal/layers' tests pass with compress/gzip listed. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

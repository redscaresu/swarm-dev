---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/pytext/decode.go, internal/pytext/compare_test.go]
estimate_lines: 130
---

# Go decodes bad UTF-8 as Python's errors="replace" and "ignore" do

Python reads bad UTF-8 with errors="replace" (bin/lib/report.py:226, bin/lib/touches_rows.py:24-28, the findings and declines readers) and with "ignore" (report.py's log_lines). internal/pytext: DecodeReplace and DecodeIgnore turn bytes into text as bytes.decode("utf-8", errors) does: one U+FFFD for each maximal invalid subsequence, as Python's decoder cuts them, where Go's own conversion gives one per byte or one per run. A comparison test runs bytes.decode and the Go over the same bytes, byte for byte: truncated sequences of 2, 3 and 4 bytes, overlong forms, encoded surrogates, a sequence above U+10FFFF, a lone continuation byte, and valid text around each.

**Done when:**
- (1) The comparison test passes. (2) It goes red when DecodeReplace alone gives a U+FFFD for each bad byte where Python gives one for the sequence, and when DecodeIgnore alone keeps a lone continuation byte, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

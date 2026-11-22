---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/eventsoutcome/eventsoutcome.go, internal/eventsoutcome/compare_test.go]
estimate_lines: 130
---

# events_outcome runs as Go beside its Python copy, under a comparison test

internal/eventsoutcome: Sep (" ~~ "), Outcome(row) and Fields(row) as bin/lib/events_outcome.py:12-30 has them. A row of 4 columns or fewer gives ""; the first Sep starts the tail; a field with no = or an empty key is skipped; a value may be empty; a later key wins. A Go test (the comparison test) runs events_outcome.py with python3 -I, bin/lib first on sys.path, and the Go over the same rows, and compares the printed results byte for byte. The rows include tests/events_test.sh's malformed cases (:303,326), the key=value tails tests/events_tail_flow_test.sh writes on every row, and: Sep at the start, several Seps, = inside a value, repeated keys, a row with no tab, non-ASCII. The test's python3 call lives in its own test file; each later package's comparison test has its own, so no story waits on a shared harness.

**Done when:**
- (1) The comparison test passes. (2) It goes red when Outcome alone takes the last Sep as the tail's start, and when events_outcome.py alone lets the first key win, each shown on a worktree copy without .git. (3) The test fails, not skips, when python3 is missing. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

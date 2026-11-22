---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/clock/compare_test.go]
estimate_lines: 100
easy: true
---

# A comparison test runs clock.py and the Go clock over the same SWARM_DASH_NOW values

The Go clock already has what clock.py has: now, today, utc_now (internal/clock/clock.go:33-77; bin/lib/clock.py:10-21). This adds only the test. A Go test runs clock.py with python3 -I, and Now, Today and UTCNow, over the same SWARM_DASH_NOW pins, and compares the printed results byte for byte: Now's epoch seconds against now(), Today against today(), UTCNow against utc_now(), and a failure as one token on each side. The pins are the ones both read alike, the rows TestPinParsing marks the same as float() (internal/clock/clock_test.go:125-139), the ones both refuse (_1700, 1700_, 17__00), and today under TZ values across a DST change. Unset is compared by the day alone, since the real clock moves. The five forms where ParseFloat and float() differ by go-layers' design (hex, spaces, Unicode digits, inf, nan; clock_test.go:140-148) are not in this comparison and are not called equal: TestPinParsing keeps pinning them (see contradictions). No Python test pins SWARM_DASH_NOW to anything but an integer (grep -rn DASH_NOW tests/).

**Done when:**
- (1) The test passes. (2) It goes red when Today alone takes the UTC day, when clock.py's today() alone does, and when Now alone refuses underscores between digits, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

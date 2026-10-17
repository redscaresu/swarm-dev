---
kind: code
status: ready
depends_on: []
touches: [tests/dash_reexec_test.sh]
easy: true
estimate_lines: 10
---

# dash_reexec_test waits for the frame instead of sleeping 3 seconds

tests/dash_reexec_test.sh:72, :77 and :91 read the dash's frame after a fixed `sleep 3`. A cold first
frame on a fresh bin/ copy took 0.8 to 3.9 seconds during split-bash (#233), so the test fails
intermittently, on main too. The file already has `within <seconds> <test...>` (line 59), which
polls every 0.2 seconds. Replace each `sleep 3` + check with `within 15 <the same check>`.
Keep any sleep that waits for something to *not* happen.

**Done when:**
- No `sleep 3` before a frame check is left in tests/dash_reexec_test.sh.
- The test passes 20 times in a row locally (the PR body gives the loop and its result).

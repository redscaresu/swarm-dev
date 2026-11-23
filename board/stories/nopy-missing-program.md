---
kind: code
status: later
touches: [tests/nopy_test.sh:nopy_wrap]
estimate_lines: 40
easy: true
---

# nopy_test.sh counts a fixture with a missing program as run

From the v0.32.0 retro (#1058). tests/nopy_test.sh's launcher (`nopy_wrap`) writes `started` before it execs the command, so a fixture whose FX_CMD names a missing program counts as run. Record the start only once the program is found, or fail when exec fails.

**Done when:**
- A fixture whose FX_CMD names a missing program fails nopy_test.sh; it passed before.
- Every fixture in tests/nopy_list.txt still passes.

---
kind: code
status: later
touches: [bin/gh-shim/gh]
estimate_lines: 60
easy: true
---

# The gh shim refuses to call itself

From the v0.32.0 retro (2026-11-20 incident). A temp copy's gh shim found itself as the next gh on PATH and recursed to 2,800 processes, hitting the per-user cap. Before it runs the real gh, the shim checks that the gh it found is not itself (or another shim, by a marker variable) and fails with a message naming the PATH entry.

**Done when:**
- A test that puts the shim's own directory twice on PATH gets an error and exit 1 within a second, not a recursion.
- The shim's existing tests (tests/gh_calls_test.sh) pass.

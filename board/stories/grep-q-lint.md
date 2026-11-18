---
kind: code
fix: true
status: ready
depends_on: []
touches: [scripts/lint:grep -q under pipefail]
---

# A lint in scripts/lint that fails a tests/*_test.sh line piping into grep -q, and the 46 sites rewritten

From the v0.31.0 retro (2026-11-17). 46 '| grep -q' lines in 25 test files can return 141 under pipefail once output passes ~64 KB (#851).

A lint in scripts/lint that fails a tests/*_test.sh line piping into grep -q, and the 46 sites rewritten.

**Done when:**
- make check fails on a fixture test file with '| grep -q'; the rewritten files pass (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

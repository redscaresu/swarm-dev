---
kind: code
fix: true
status: ready
depends_on: []
touches: [tests/test_helpers.sh:stop group helper]
---

# One process-group stop helper in tests/test_helpers.sh, used by the files that start background processes

From the v0.31.0 retro (2026-11-17). Test files stop their background children in different ways, and 29 EXIT traps stop nothing (flaky-tests readings).

One process-group stop helper in tests/test_helpers.sh, used by the files that start background processes.

**Done when:**
- a test that starts a sleeping child leaves no process after its EXIT trap; with the helper removed the child survives (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

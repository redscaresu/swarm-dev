---
kind: code
status: later
depends_on: []
touches: [tests/:shellcheck list test]
---

# A test that the two lists name the same files

From the v0.31.0 retro (2026-11-17). The Makefile's and CI's shellcheck file lists can drift (triage group).

A test that the two lists name the same files.

**Done when:**
- the test fails when a file is in one list only (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

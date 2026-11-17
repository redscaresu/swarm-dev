---
kind: code
status: later
depends_on: []
touches: [scripts/lint:|| true swallow]
---

# A lint over bin/ that lists '|| true' with no comment saying why the failure is safe to ignore

From the v0.31.0 retro (2026-11-17). fails-open (44 PRs) and fails-silent (26 PRs) are the commonest recurring kinds after rules-unchecked.

A lint over bin/ that lists '|| true' with no comment saying why the failure is safe to ignore.

**Done when:**
- make check fails on a fixture line with a bare '|| true'; one with a reason comment passes (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

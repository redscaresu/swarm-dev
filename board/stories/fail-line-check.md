---
kind: code
status: later
depends_on: []
touches: [bin/lib/build.sh:review brief FAIL-line pre-check]
---

# At review-agent start, list the PR's new tests with no FAIL line in its body, so the reviewer flags them first

From the v0.31.0 retro (2026-11-17). rules-unchecked is the commonest recurring kind: 76 PRs where a new test had no FAIL line quoted in the PR body. The user filed it for v0.32 at the v0.31.0 retro.

At review-agent start, list the PR's new tests with no FAIL line in its body, so the reviewer flags them first.

**Done when:**
- a fixture PR adding a test with no FAIL line in its body gets the list in its brief; one with the line does not (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

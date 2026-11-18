---
kind: code
status: later
depends_on: []
touches: [bin/lib/merge.sh:protected-path hold]
---

# Hold a protected-path PR for the user whatever the merge mode or grant

From the v0.31.0 retro (2026-11-17). Under merge = human with an HLD merge grant, a PR changing .claude/, .github/, hooks/ or the Makefile is not held (#661, #595). The user chose to hold it too at the v0.31.0 retro.

Hold a protected-path PR for the user whatever the merge mode or grant.

**Done when:**
- a fixture granted PR changing hooks/ is held; with the change removed it merges (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

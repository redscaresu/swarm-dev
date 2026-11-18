---
kind: code
status: later
depends_on: []
touches: [bin/lib/merge.sh:merge_pr red base]
---

# Refuse a story PR's merge while the base's head is red, except a fix-main story's PR

From the v0.31.0 retro (2026-11-17). swarm.sh merge has no check that the base is green, so a review agent can merge onto a red main (#666). The user chose to refuse it at the v0.31.0 retro.

Refuse a story PR's merge while the base's head is red, except a fix-main story's PR.

**Done when:**
- a fixture with a red base refuses a story merge and allows a fix-main merge (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

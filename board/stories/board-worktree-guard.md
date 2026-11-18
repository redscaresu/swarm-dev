---
kind: code
status: later
depends_on: []
touches: [bin/swarm.sh:board-reading commands from _board worktree]
---

# Refuse board-reading commands run from a _board-* worktree, naming the main checkout to run from

From the v0.31.0 retro (2026-11-17). A builder once ran swarm.sh story --strict from a _board-* worktree and read its stale board (#739). The user filed a guard for v0.32 at the v0.31.0 retro.

Refuse board-reading commands run from a _board-* worktree, naming the main checkout to run from.

**Done when:**
- story --strict run from a fixture _board-x worktree is refused; from the main checkout it runs (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

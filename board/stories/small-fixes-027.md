---
kind: code
status: later
depends_on: []
touches: [tests/review_test.sh, bin/lib/agents.sh:start reading, bin/lib/flow_lead_queue.py, scripts/lint loose-match, bin/lib/dash_finished.py:BOARD_OWN, bin/lib/init.sh:Board.base]
estimate_lines: 150
easy: false
---

# Small fixes from the 0.27 retro

For 0.28 (0.27 retro, 2026-10-25). Split this when it is planned if it runs over one PR.
- The review_test watch test dies on "Broken pipe" on stdout, then passes on a rerun (a flake).
- herdr reports a review agent's start as "unclear" while the agent runs and writes its review.
- A builder hit a permission prompt on `rm -rf "$SP/$m"`.
- Older items: the lead_queue keep rule; the loose-match lint missing `=~`; commands/epic.md and hld.md step 5 lacking a board-pr worktree; dash_finished's BOARD_OWN missing hld/; init never updating an existing Board.base.
- Remove the stale `swarm-dev-wt/fix-pin-ubuntu` worktree and its branch `fix/pin-ubuntu-24`. #334 made CI pass on ubuntu-latest, so the pin is obsolete.

**Done when:**
- A test for each code fix fails before the fix and passes after it. The flake does not fail in 20 runs.
- `make test` passes.

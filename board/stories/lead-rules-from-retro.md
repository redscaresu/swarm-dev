---
kind: code
status: ready
depends_on: []
touches: [commands/swarm.md:routine lead calls, commands/swarm.md:force-push rule]
---

# Add both to commands/swarm.md's lead rules

From the v0.31.0 retro (2026-11-17). Two rules the user agreed at the v0.31.0 retro: the lead makes routine swarm calls (restart builders, reviews, conductors, load) without asking and logs each with swarm.sh intervene (memory swarm-lead-decides); and a lead's --force-with-lease on a story/* branch the swarm owns is routine, only after checking the same diff and a signed commit, logged with intervene.

Add both to commands/swarm.md's lead rules.

**Done when:**
- commands/swarm.md has both rules; doc_check_test passes (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

---
kind: code
status: later
depends_on: []
touches: [bin/lib/agents.sh:name_clash callers]
---

# Run the 32-character clash check on builder, step-up and restart starts too

From the v0.31.0 retro (2026-11-17). name_clash (bin/lib/agents.sh:663-668, #965) runs only on swarm.sh agent starts; builder, step-up and restart starts skip it (#965 review x3).

Run the 32-character clash check on builder, step-up and restart starts too.

**Done when:**
- a builder start whose 32-character cut clashes with a running agent is refused; with the change removed it starts (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

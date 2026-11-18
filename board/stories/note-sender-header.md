---
kind: code
status: later
depends_on: []
touches: [bin/lib/agents.sh:tell note header]
---

# Head a note with its real sender: the lead, a conductor or a review agent

From the v0.31.0 retro (2026-11-17). tell heads every note 'From the lead', whoever sends it (bin/lib/agents.sh:2259; #593, #603, #623), which misleads the agent reading it.

Head a note with its real sender: the lead, a conductor or a review agent.

**Done when:**
- a note sent from a conductor's session is headed with the conductor's name; with the change removed it says 'From the lead' (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

---
kind: code
status: later
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_queue failed read]
---

# Print one line naming the failed read and keep the item for the next poll

From the v0.31.0 retro (2026-11-17). lead_queue drops a read that fails instead of reporting it, so the lead hears nothing (triage cluster).

Print one line naming the failed read and keep the item for the next poll.

**Done when:**
- a stubbed failing read prints the line; with the change removed nothing is printed (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

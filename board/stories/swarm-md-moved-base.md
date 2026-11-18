---
kind: code
status: later
depends_on: []
touches: [commands/swarm.md:moved-base steps]
---

# Rewrite them to match bin/lib/merge.sh

From the v0.31.0 retro (2026-11-17). commands/swarm.md's moved-base steps are out of date with merge's current behaviour (triage cluster).

Rewrite them to match bin/lib/merge.sh.

**Done when:**
- doc_check_test passes and the steps name only commands swarm.sh has (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

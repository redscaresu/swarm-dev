---
kind: code
status: later
depends_on: []
touches: [bin/lib/lifecycle.sh:wait_lead network stop]
---

# wait --lead prints a line for an agent stopped on a network error that no wait is resuming

From the v0.31.0 retro (2026-11-17). On 2026-11-16/17 a builder stopped on a network error at 18:40 and another sat idle on an ended background run; nothing woke the lead for ~14 h (incident 783).

wait --lead prints a line for an agent stopped on a network error that no wait is resuming.

**Done when:**
- a fixture pane ending on 'Can't reach the API server' gives a line; with the change removed nothing (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

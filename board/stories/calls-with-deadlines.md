---
kind: code
status: later
depends_on: []
touches: [bin/lib/agents.sh:claude_agents within, bin/lib/lifecycle.sh:poll_while seconds, tests/timeouts_test.sh:call list]
---

# Wrap the sites in within, make poll_while count seconds, and add claude agents and herdr list calls to tests/timeouts_test.sh

From the v0.31.0 retro (2026-11-17). claude agents --json (bin/lib/agents.sh:891) and herdr agent/workspace list have no deadline; poll_while counts grace in polls, not seconds (#841, #858); release_stage's gh calls can outlast lead-stop's 45 s budget (#970).

Wrap the sites in within, make poll_while count seconds, and add claude agents and herdr list calls to tests/timeouts_test.sh.

**Done when:**
- tests/timeouts_test.sh lists claude agents and herdr agent list; a hung stub makes each return within its bound (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes

**Folded into the v0.32 Python rewrite (the user, 2026-11-18):** not built in bash. The v0.32 HLD names this as a requirement of the command it ports, with this story's Done when as the test the Python version must pass; this file goes when that plan absorbs it.

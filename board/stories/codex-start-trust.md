---
kind: lead
status: ready
depends_on: []
touches: []
estimate_lines: 120
easy: false
---

# Lead: emergency patch v0.29.1, a codex agent starts inside a git repo

The user asked for this fix as an emergency patch on 2026-10-29. On v0.29.0 every `swarm.sh agent ... codex` start failed: codex 0.164 asks "Trust this folder?" inside a git repo it has not trusted, so the start blocked and herdr refused it as not ready, and the retry in the same pane then failed as agent_name_taken. The lead builds the fix by hand (bin/lib/agents.sh start_agent: a session-only `-c projects=...` trust override that respects a repo codex's config marks untrusted, and a retry in a fresh pane after a not-ready refusal only), with regression tests in tests/review_test.sh, then cuts v0.29.1 and upgrades.

**Done when:**
- The fix PR has merged with its regression tests, and v0.29.1 is tagged and released.
- A `swarm.sh agent scope-<epic> <name> <dir> codex <brief>` start on v0.29.1 starts codex and sends its brief.

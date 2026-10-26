---
kind: code
status: later
depends_on: []
touches: [bin/lib/agents.sh:start_agent, bin/lib/lifecycle.sh:wait_lead story-file reads]
estimate_lines: 60
easy: true
---

# Two small v0.28.0 retro bugs: the codex agent name, and noise after a merge

- `swarm.sh agent <tab> codex ... codex <brief>` fails with herdr `agent_name_taken`, for any name (codex, codex-plan), though no agent of that name exists (2026-10-25, plan-hld's codex step). The lead ran codex directly instead.
- wait --lead prints `sed:` or `awk: can't open file board/stories/<slug>.md` when a merge removes a story file between its list and its read.

**Done when:**
- A test starts a codex-role agent with herdr stubbed, and it is not refused.
- A test removes a story file mid-poll, and wait --lead prints no sed or awk error.

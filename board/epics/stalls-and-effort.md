---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# stalls-and-effort

No step-up while a builder's own tests run, and effort that pays for itself

HLD § v0.31.0 additions. In the v0.30.0 build 13 of 19 step-ups to Fable came from the stall check, several about 2.5 hours into the builder's own full test run, past the 90-minute allowance; an escalate build costs $46.65 against $20.84. Opus at xhigh cost $94.86 per merged story against $29.94 at high, for 80% against 77% first-attempt merges.

**Done when:**
- stage: v0.31.0
- The stall check never steps up a builder while its own test process is alive, whatever the allowance; a test with a long-running fake test run sees no step-up.
- A one-wave trial runs risk: high stories at effort high instead of xhigh, and `flow model_fit` compares cost and first-attempt merges against the v0.30.0 build; the user decides from the figures.

**Out of scope:**
The ladder threshold (kept at 3 by the user on 2026-10-31).

**Constraints:**
- stage: v0.31.0. From the HLD's v0.31.0 additions (decided 2026-10-31); /plan-epic scopes it.

**Areas:** bin/lib/agents.sh (agent_stalled), bin/lib/panes.py (test allowance), .claude/swarm/config (effort)

**Your part:**
- none

---
kind: docs
status: ready
epic: dev-rules-docs
depends_on: []
touches: [commands/swarm.md:the lead's rules, tests/swarm_lead_rules_test.sh (new)]
estimate_lines: 40
easy: true
---

# commands/swarm.md: three rules for the lead, from the v0.28.0 retro

Kept as on the board (epic: less-noise); the lead adds it to the epic's Done when. commands/swarm.md's rules for the lead gain: plan epics whose plans do not depend on each other at the same time, a cross-epic order going in a story's depends_on once the other plan exists; restart an agent at its first 'Request timed out' or API-error stop its own retries did not clear, with a brief that writes its output as it goes; judge whether an agent is alive from events.tsv and its PR, never from a pane read alone.

**Done when:**
- tests/swarm_lead_rules_test.sh (new) pins each of the three rules in commands/swarm.md; each check fails when its rule is removed.

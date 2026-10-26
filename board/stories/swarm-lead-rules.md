---
kind: docs
status: later
epic: less-noise
depends_on: []
touches: [commands/swarm.md:the lead's rules]
estimate_lines: 30
easy: true
---

# commands/swarm.md: three rules for the lead, from the v0.28.0 retro

The lead made three avoidable mistakes during v0.28.0 (2026-10-25/26, logged as interventions): it planned four independent epics one after another; it waited 25 minutes on an agent whose requests were timing out before restarting it (68 minutes lost); and it read two conductors as idle from a pane that was scrolled up, when events.tsv showed them working. Add to commands/swarm.md's rules for the lead:
- Plan epics whose plans do not depend on each other at the same time; a cross-epic order goes in a story's scope as a sentence, not in depends_on.
- Restart an agent at its first "Request timed out" or API-error stop that its own retries did not clear, with a brief that writes its output as it goes.
- Judge whether an agent is alive from events.tsv and its PR, never from a pane read alone.

**Done when:**
- commands/swarm.md has the three rules, and a test on its text pins each.

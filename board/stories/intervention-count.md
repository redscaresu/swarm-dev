---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:intervene command, bin/lib/flow_incidents.py, bin/lib/dash_render.py:speedometer, commands/swarm.md, tests/]
---

# Count each time a person had to step in

The clearest measure of a self-running swarm is how often someone had to step in. On 2026-10-18 it
was three: the lead typed into a stalled conductor's pane, and the user found the held stories and
the slow CI by asking. Add `swarm.sh intervene <kind> "<one line>"` (kinds: `lead-hand`, the lead
acted by hand where a command should have; `user-caught`, the user found a problem first), which
logs to events.tsv. commands/swarm.md tells the lead to log one for every such moment. `flow` counts
them per day and per kind, and dash shows the 7-day count beside the speedometer.

**Done when:**
- `intervene` with an unknown kind fails and logs nothing; a valid one adds one events.tsv line.
- flow and dash show the same 7-day count on a fixture (agreement assertion).
- commands/swarm.md names both kinds, and a test greps it.

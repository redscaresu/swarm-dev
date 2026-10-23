---
kind: code
status: ready
depends_on: []
touches: [bin/lib/flow_time_in_state.py, bin/lib/flow_idle_slots.py (new), tests/flow_test.sh]
easy: false
estimate_lines: 150
---

# flow shows how often ready work waited while builder slots sat idle

The second half of flow-ready-wait's title was never built (#378, logged by the backlog conductor on 2026-10-23). On 2026-10-22 the user asked why so few agents ran while stories sat ready. ready_wait shows how long one story waited. It doesn't show whether the swarm as a whole was idle while work was ready.

Using the events log (builds' start and end, stories' ready times, a conductor's running span), add a flow section, idle_slots. Per epic and in total, show the minutes when at least one story was ready with no build while its conductor ran, and the most stories ready at once. A gap where no conductor ran is counted separately, as "no conductor". Builds that clashed are not counted as idle: a ready story that clashes with a running one isn't startable.

**Done when:**
- tests/flow_test.sh: a fixture event log with a conductor running, story A ready from minute 0 and built from minute 10, and story B building throughout, shows 10 idle minutes. The same with A clashing with B (touches) shows 0. A gap with no conductor shows under "no conductor".
- `swarm.sh flow` on this repo quotes idle_slots for safer-faster-swarm in the PR.

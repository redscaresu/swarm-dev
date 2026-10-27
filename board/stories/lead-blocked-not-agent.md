---
kind: code
status: ready
epic: conductor-hands-off
depends_on: []
touches: [bin/lib/board.sh:lead_blocked (new), bin/lib/board.sh:blocking_leads, bin/lib/board.sh:blocked_why, bin/lib/board.sh:waiting_on_user, docs/reference.md:next and status lines, tests/lead_blocked_test.sh (new)]
estimate_lines: 100
easy: true
---

# next and status say when a blocked story waits on the lead, not an agent

Lanes-review item: a story blocked on work no agent will do must not read as an agent's. Add lead_blocked <story-file> (new): true when every open depends_on parent is a kind: lead story or a story blocked with no depends_on (blocked_why's `by hand: no depends_on`, bin/lib/board.sh:1341-1348). blocking_leads (board.sh:493-514), printed under a running conductor's `wait` step (board.sh:257-259), names only a ready kind: lead parent; also print `also: lead <parent> blocks <slugs>` for a by-hand blocked parent, so commands/swarm.md needs no new arm. status's blocked line is built in waiting_on_user (board.sh:1248) from blocked_why: when lead_blocked holds, it reads `blocked: <slug> (by <parents>, which no agent builds)`. conductor-report-hold uses lead_blocked; the stop_rule half of this item is its.

**Done when:**
- tests/lead_blocked_test.sh (new): with a conductor running, a story blocked on a parent that is blocked with no depends_on gets `also: lead <parent> blocks <child>` from next. Fails on today's code, which prints nothing for it; the ready kind: lead parent case prints as before.
- The same test: status reads `blocked: <child> (by <parent>, which no agent builds)` for a kind: lead parent and for a by-hand blocked parent, and `blocked: <child> (by <parent>)` as today for a parent an agent builds.

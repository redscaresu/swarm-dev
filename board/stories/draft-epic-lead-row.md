---
kind: code
status: blocked
epic: fixes-027
depends_on: [epic-guard-gaps]
needs: [epic-guard-gaps: epic_ticket_parent and hld_ticket in bin/lib/board.sh; it also edits waiting_on_user's later-epic hint and the gate handler's later-epic line]
touches: [bin/lib/board.sh:waiting_on_user draft arm, bin/lib/dash_render.py:draft rows, commands/swarm.md:gate handler draft epic line, tests/next_test.sh:draft epic cases, tests/dash_needs_you_test.sh:draft epic cases, tests/lead_handler_test.sh:gate handler lead_epics case]
estimate_lines: 120
easy: false
---

# next and dash show a draft epic the lead may set active as the lead's

Uses epic-guard-gaps' ticket helpers (epic_ticket_parent, hld_ticket) and shares waiting_on_user and the swarm.md gate handler with it. waiting_on_user's draft arm (bin/lib/board.sh:1265-1267) prints `draft epic: <slug>, run /epic <slug>` for every unstaged draft. That includes drafts the lead may set active itself (commands/swarm.md:487-489): a parent: naming an epic that is active or split, an hld: naming an agreed HLD that grants epics, or any draft when lead_epics = on. Test the first two with epic-guard-gaps' helpers, through a reader over the board's own files, so the gate and the guard agree. Print those drafts as a lead line that names why, e.g. `draft epic: <slug>, the lead sets it active (<why>)`. In dash_render.py, put them in the lead's queue and leave them out of the 'agree draft epic' needs-you rows (:331-332, :424-426). In commands/swarm.md's gate handler, read lead_epics with `swarm.sh config lead_epics`, not from .claude/swarm/config (:489).

**Done when:**
- tests/next_test.sh: a draft with an active parent:, one under an HLD that grants epics, and any draft under lead_epics = on each show the lead line, not 'run /epic'. A plain draft still shows 'run /epic'. Fails on the base.
- tests/dash_needs_you_test.sh with lead = session: the three are in the lead's queue, not needs you, and the plain draft keeps its 'agree draft epic' row. Fails on the base.
- tests/lead_handler_test.sh pins `swarm.sh config lead_epics` in the gate handler. Fails on the base.

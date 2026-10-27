---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/dash.sh:dash_render env, bin/lib/dash_render.py:awaiting rows, bin/lib/dash_render.py:plan and finish rows, docs/reference.md:dash needs you, tests/dash_needs_you_test.sh:merge row cases]
estimate_lines: 150
easy: false
---

# dash puts each merge row in the queue of whoever merges it

Under lead = session, dash_render (bin/lib/dash_render.py:339-345, :386-387) puts every 'awaiting your merge' row, and the plan and finish PR rows, in the lead's queue. Route each to whoever merges it. Under merge = human: an 'awaiting your merge' row is the user's unless the item's agreed HLD grants merge and it does not cost money; a plan PR row is the user's unless its HLD grants merge; a finish PR row is the user's, grant or not (commands/swarm.md:376). Under merge = agent, keep today's rule: costs money is the user's, the rest the lead's. dash learns the grant from a DASH_GRANTED list that dash.sh's dash_render builds once a frame, from board files only (item_hld and hld_grants, over the review items and the HLDs with an open plan PR). No gh call, since dash runs every frame. Update the comment at :341-342 and docs/reference.md's dash needs-you text.

**Done when:**
- tests/dash_needs_you_test.sh with lead = session and merge = human: a review story under an HLD that grants merge is in the lead's queue, not needs you; the same story with costs: money is in needs you; one under no grant is in needs you. Fails on the base.
- Same settings: an open finish PR under a granting HLD is in needs you. An open plan PR is in the lead's queue with the grant and in needs you without. Fails on the base.
- Under merge = agent the rows land where they do today; a case pins it.

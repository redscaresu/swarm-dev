---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/dash.sh:agent list, cost read, bin/lib/dash_render.py, tests/fixtures/dash/golden-*.txt (regenerate if present), tests/dash_defects_test.sh (new)]
easy: false
estimate_lines: 180
---

# Fix dash's three wrong numbers: the agents count, the shared cost and the waiting epics

Builds on the split: dash's agent list and cost read in bin/lib/dash.sh, and bin/lib/dash_render.py. Fixes the three defects seen on 2026-10-17. The agents count read 0 while status listed a working conductor and builder: dash reads the agent list status uses. Both frames showed the same '$80.60 today': the cost is read per project. Unplanned epics waiting on their dependencies were listed as 'active epics with no open story': they are named as waiting on those epics. Each fix gets a test that fails when the fix is reverted. Regenerate golden frames if they are on your base.

**Done when:**
- tests/dash_defects_test.sh: with a status stub listing working agents, dash's count matches it; with two projects whose cost logs differ, each frame shows its own cost; an epic with unmet depends_on is shown as waiting on them, not under 'no open story'.
- Reverting any one of the three fixes (the PR body shows how it was checked) makes its case fail.

---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [commands/plan-epic.md:agents section, commands/plan-hld.md:agents section, tests/plan_epic_test.sh:close line check, tests/plan_hld_test.sh:close line check, docs/reference-planning.md:Scoping an epic, docs/reference-planning.md:Decomposing an HLD]
estimate_lines: 25
easy: true
---

# Planning agents' panes close once their output is read

#690: 15 planning panes stayed open for hours (HLD:91-92). commands/plan-epic.md (agents started at :18) and commands/plan-hld.md (:69) tell the lead to run `swarm.sh close <name>` for each planning agent (survey, lead, critic, skeptic, split-critic) once it has read that agent's `<name>.json`, never while only a `.partial` exists (that agent may be started again, plan-epic.md:29). A planning pane still working is left open, and the lead's report names it (the epic's Done when 2): the close line says so.

**Done when:**
- tests/plan_epic_test.sh and tests/plan_hld_test.sh each pin the close line and its never-on-.partial clause; each check goes red with the line removed.
- Each pinned close line also says a pane still working is left open and named.
- docs/reference-planning.md's Scoping an epic and Decomposing an HLD sections say the panes close once read.

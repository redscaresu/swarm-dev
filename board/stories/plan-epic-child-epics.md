---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [commands/plan-epic.md, bin/lib/board.sh:plannable_epic, bin/lib/board.sh:next_step, templates/docs/epics/README.md:parent row, tests/plan_epic_test.sh, tests/plan_epic_children_test.sh (new)]
easy: false
estimate_lines: 150
---

# /plan-epic splits a large epic into child epics instead of stories

Builds on the split: plannable_epic and next_step in bin/lib/board.sh (bin/swarm.sh:3192). commands/plan-epic.md step 0 sizes the epic. A small or medium one becomes stories, as now. A large one becomes child epics (epics/<child>.md with `parent: <epic>` and its own Done when), each planned when next offers it. A parent counts as done when none of its children is left on the board. templates/docs/epics/README.md documents parent:.

**Done when:**
- A grep in tests/plan_epic_test.sh finds step 0's large-epic arm and the child-epic file shape (parent:, Done when) in commands/plan-epic.md.
- tests/plan_epic_children_test.sh: on a fixture board with a parent and two `parent:` children and no stories, `next` offers plan-epic for the first child; the parent counts as done only when both child files are gone.

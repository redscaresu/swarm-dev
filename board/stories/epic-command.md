---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [commands/hld.md -> commands/epic.md, bin/swarm.sh:ROLE_GROUPS and policy, bin/lib/board.sh:next_step, bin/lib/board.sh:plannable_epic, templates/docs/epics/README.md:status row, commands/swarm.md:hld arm, skills/swarm-dev/SKILL.md:body, README.md:§ steps, docs/method.md:§ planning chain, tests/command_names_test.sh, tests/roles_test.sh, tests/next_test.sh:hld and draft cases]
easy: false
estimate_lines: 280
---

# /epic replaces /hld: the user and the lead co-write a draft epic, an epic reviewer attacks it, and nothing plans it until the user agrees

Builds on the split: next_step and plannable_epic in bin/lib/board.sh, ROLE_GROUPS and policy (bin/swarm.sh:269,276). commands/hld.md becomes commands/epic.md. It co-writes the board's epics/<slug>.md with the sections Problem (with evidence), Goals (checkable), Non-goals and Constraints, as `status: draft`, and the hld-review role becomes epic-review and attacks the draft. The epic becomes `status: active` only when the user agrees. plannable_epic skips a draft epic, and next_step offers /epic where it offered /hld and names a draft epic as waiting on the user. templates/docs/epics/README.md documents draft. command_names_test records /epic as it does /hld (tests/command_names_test.sh:3-13). SKILL.md's body and README name /epic. /plan-hld and the HLD type are remove-plan-hld's.

**Done when:**
- tests/command_names_test.sh passes with commands/epic.md and no commands/hld.md; a grep in tests/plan_epic_test.sh finds in commands/epic.md the epics/ path, the four section headings and the step that sets active only on the user's agreement.
- tests/roles_test.sh: epic-review is in ROLE_GROUPS and policy; hld and hld-review are not.
- tests/next_test.sh: `next` on a board holding a draft epic does not offer plan-epic for it, and does once its status is active; on a board with no epic it prints the /epic step.

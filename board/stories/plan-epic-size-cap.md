---
kind: docs
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [commands/plan-epic.md, templates/docs/stories/README.md:estimate_lines and easy rows, tests/plan_epic_test.sh]
easy: true
estimate_lines: 90
---

# plan-epic caps a story at one command or behaviour and about 300 lines, and labels estimate_lines and easy

commands/plan-epic.md step 2 asks the lead for estimate_lines and easy per story (easy: under about 100 lines, no new command, no shared helper in bin/swarm.sh) and caps a story at one new command or one changed behaviour and about 300 lines. Step 3's skeptic refutes a story over the cap, the report lists each estimate, and story files get estimate_lines and easy front matter. templates/docs/stories/README.md documents both keys.

**Done when:**
- tests/plan_epic_test.sh checks the cap in step 2 and step 3, estimate_lines and easy in the output shape and the story front matter, and the estimate in the report.

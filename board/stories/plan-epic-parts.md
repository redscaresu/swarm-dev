---
kind: docs
status: ready
epic: clash-by-part
depends_on: []
touches: [commands/plan-epic.md:touches and split critic, tests/plan_epic_test.sh:touches line, tests/split_critic_test.sh:bare-file finding]
estimate_lines: 70
easy: true
---

# /plan-epic writes file:part touches, and its split critic flags a bare file

commands/plan-epic.md tells planners how to write `touches`. Make it say: write `file:part`, the part starting with a function or section name, and a bare file only when the story changes the whole file (a bare file now clashes only with the same bare file). The split critic (commands/plan-epic.md:41-60) reports a child or story whose touches names a bare file as a finding, with the part it should name. Run the humanizer over the changed prose.

**Done when:**
- tests/plan_epic_test.sh pins the file:part instruction, and tests/split_critic_test.sh pins the bare-file finding; each goes red if its line is removed.
- `make test` passes.

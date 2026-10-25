---
kind: docs
status: blocked
epic: clash-by-part
depends_on: [part-overlap]
needs: [part-overlap: the first-token rule in bin/lib/touches_rows.py:overlap, which the planner text describes]
touches: [commands/plan-epic.md:touches and the critics, tests/plan_epic_test.sh:touches line, tests/split_critic_test.sh:bare-file finding]
estimate_lines: 70
easy: true
---

# /plan-epic writes file:part touches, and its split critic flags a bare file

commands/plan-epic.md tells planners how to write `touches`. Make it say: write `file:part`, the part starting with a function or section name, and a bare file only when the story changes the whole file (a bare file now clashes only with the same bare file). Needs part-overlap's first-token rule, so the planner text never describes a check that is not live yet. Three reviewers flag a bare-file touches, each where it can see one: the ordinary critic (step 3) for every story; the small path, where the lead's own codex pass is the only review, through a line in its instructions; and the split critic (commands/plan-epic.md:41-60) for a child epic's touches. Each finding names the part to write instead. Run the humanizer over the changed prose.

**Done when:**
- tests/plan_epic_test.sh pins the file:part instruction and the critic's and small path's bare-file check, and tests/split_critic_test.sh pins the split critic's; each goes red if its line is removed.
- `make test` passes.

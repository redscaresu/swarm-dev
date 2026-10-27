---
kind: docs
status: ready
epic: fixes-027
depends_on: []
touches: [commands/hld.md:step 5, commands/epic.md:step 5, commands/plan-hld.md:Resuming, commands/swarm.md:plan-hld arm, tests/hld_command_test.sh:step 5 order cases, tests/plan_hld_test.sh:resume cases, tests/lead_handler_test.sh:plan-hld arm cases]
estimate_lines: 90
easy: true
---

# hld.md and epic.md open their board PR from a worktree; plan-hld resumes and reads grants from origin

Merge after less-noise's codex-skip story, which edits the same step-5 paragraphs (commands/hld.md:79, commands/epic.md:91) and commands/plan-hld.md:129; the lead adds it to depends_on once it has a slug. (1) Step 5 of commands/hld.md (:77-84) and commands/epic.md (:88-94) opens a board PR with no worktree. Write the agreement in one, in this order: `swarm.sh board-pr start`, edit and commit in the worktree, `swarm.sh codex-review` there, `swarm.sh board-pr open`, as commands/plan-epic.md:36-39 does. A board outside the repo keeps its in-place path. (2) The Resuming paragraph of commands/plan-hld.md (:77-80) reuses outputs newer than <wt>/.git, so a rerun whose worktree was removed reruns every agent. Say what to compare against when <wt> is new, e.g. origin's last change to the HLD. (3) The plan-hld arm of commands/swarm.md (:365-367) reads `swarm.sh grants <hld>` from the main checkout. Say to read origin's copy, and where. Run the humanizer over the changed prose.

**Done when:**
- tests/hld_command_test.sh, for both hld.md and epic.md step 5: board-pr start comes before the commit, the commit before codex-review, and codex-review before board-pr open, and the commit and codex-review run in the worktree. Fails on the base.
- tests/plan_hld_test.sh pins the reference the Resuming rule compares against when the worktree is new. tests/lead_handler_test.sh pins that the plan-hld arm reads grants from origin's copy, after the step that gets it. Both fail on the base.

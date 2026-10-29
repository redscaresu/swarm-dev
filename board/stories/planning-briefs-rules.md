---
kind: docs
status: blocked
epic: rules-file
depends_on: [rules-file-briefs]
needs: [rules-file-briefs (rules.md at the plugin root)]
touches: [commands/hld.md:step 2 co-author brief, commands/epic.md:step 2 co-author brief, commands/plan-hld.md:Write in <wt> paragraph, tests/command_names_test.sh:humanizer cases, docs/reference.md:Writing an HLD, docs/reference.md:Writing an epic, commands/plan-epic.md:ground rules, commands/plan-hld.md:ground rules]
estimate_lines: 80
easy: true
---

# Planning and co-author briefs read rules.md and run the humanizer over their prose

Needs rules-file-briefs' rules.md (its path at the plugin root). This is Appendix B's item: every human-facing text goes through the humanizer, which today only commands/swarm.md:564 asks for (release docs). Add the step where a command's agent writes prose a person agrees. The HLD co-author's brief (commands/hld.md step 2, :64-77) and the epic co-author's brief (commands/epic.md step 2, :80-91) run the humanizer skill over the draft's prose before they touch D/ready and after each revision. /plan-hld runs the same pass over its epic files before the board PR (commands/plan-hld.md, the Write in <wt> paragraph, :131). Stories and briefs are for agents and need none (AGENTS.md). The humanizer is another plugin, so the step says what to do when it is not installed: say so and go on. A project without it is not blocked. Name the pass in docs/reference.md § Writing an HLD and § Writing an epic. Add assertions to tests/command_names_test.sh, which already reads every command file, and update its header comment. Rules reach the planning agents too (the 0.30 HLD's Goal 7 says every agent; codex and the critic found the plan left them out): the briefs these commands write for the HLD and epic co-authors and their reviewers (commands/hld.md:62-77, commands/epic.md:78-91) and for plan-epic's survey, lead, skeptic, critic and codex agents (commands/plan-epic.md, the ground rules every brief begins with) and plan-hld's agents tell the agent to read ${CLAUDE_PLUGIN_ROOT}/rules.md first.

**Done when:**
- The co-author briefs in commands/hld.md and commands/epic.md, and the epic-writing step in commands/plan-hld.md, each tell the agent to run the humanizer over its prose and what to do when the skill is missing.
- tests/command_names_test.sh fails when any of hld.md, epic.md, plan-hld.md or swarm.md stops naming the humanizer. This is shown by removing it from one, with the FAIL line in the PR body.
- docs/reference.md § Writing an HLD and § Writing an epic name the pass.
- The co-author and reviewer briefs in commands/hld.md and commands/epic.md, and the ground rules in commands/plan-epic.md and commands/plan-hld.md, name ${CLAUDE_PLUGIN_ROOT}/rules.md; tests/command_names_test.sh fails when any of them drops it (FAIL line in the PR body).

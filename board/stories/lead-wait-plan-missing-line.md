---
kind: code
status: blocked
epic: board-loose-ends
depends_on: [lead-wait-planned-line]
needs: [lead-wait-planned-line (plan_lines; its Plan swarm lines paragraph and tests/plan_lines_test.sh)]
touches: [bin/lib/lifecycle.sh:plan_lines (plan-missing check), bin/lib/agents.sh:plan attempt record (expected agents), tests/plan_lines_test.sh:plan-missing cases, tests/lead_handler_test.sh:KINDS, docs/reference-lead.md:Plan swarm lines, commands/swarm.md:planned line handling (wait --lead step)]
estimate_lines: 130
easy: false
---

# wait --lead prints `plan-missing:` when a plan agent ended without its output (#762, part 2)

Needs from lead-wait-planned-line: plan_lines and tests/plan_lines_test.sh. #762 (open): nothing tells the lead when a plan swarm's agents finish. On 2026-10-30 three plans finished at about 15:00, and the lead learned it from the user at 15:02 (incident 15:07:51Z). A planning tab's record, .swarm/state/scope-<epic> (plan-<hld> for /plan-hld), lists `<pane> <agent>` for each agent still open (e.g. scope-lead-woken: `w30:p3 critic`). Each agent writes .swarm/<epic>/<name>.json, with a .partial while it works (commands/plan-epic.md:30-33; bin/lib/agents.sh:754-768). <name> is the record name less a trailing -<epic>: survey-<epic> gives survey.json, critic gives critic.json, skeptic-<story> gives skeptic-<story>.json. An output counts only when it is valid JSON and fresh by its planner's own resume rule: for /plan-epic, newer than the epic file (commands/plan-epic.md:28), and for a split critic, newer than its worktree (:41); for /plan-hld, newer than the attempt's base-rev (commands/plan-hld.md:94). A malformed file or one from an earlier attempt does not. A critic that failed to start on 2026-10-30 showed only in a script's log. Add to plan_lines: for each agent the current attempt expects, a `plan-missing: <epic> <name> ended without its output, exit: /swarm-dev:plan-epic <epic> (it starts that agent again)` line when the agent has ended and has no counted .json. Track the expected agents for the attempt apart from the live tab record: next_pane prunes failed and dead panes before the next start (bin/lib/agents.sh:207, 330), so an agent that failed to start or whose pane closed drops out of the record and would never be named. Tell a working agent from an ended one: an agent still listed by herdr but no longer running counts as ended. Use the poll's existing herdr list (LEAD_AGENTS), no new read; a poll with no herdr list prints no plan-missing: line. Add `plan-missing` to tests/lead_handler_test.sh's KINDS. Docs: the same `Plan swarm lines` paragraph and commands/swarm.md handling. PR body: Closes #762.

**Done when:**
- tests/plan_lines_test.sh: with critic.json missing and critic no longer running, the poll prints `plan-missing: e critic ...`. With critic working and only critic.json.partial present, it prints no line.
- A critic that failed to start, followed by a sibling's start that pruned its pane from the record, still gives `plan-missing: e critic`. So does a closed critic pane, and a critic herdr still lists as ended with only a .partial.
- A poll with no herdr list prints no plan-missing: line.
- Removing the missing-agent check (copy-aside proof) turns the first case red.
- tests/lead_handler_test.sh's KINDS has plan-missing, and it passes. tests/doc_check_test.sh, shellcheck and scripts/select-tests.sh --run pass.
- An ended agent whose .json is malformed, or older than its freshness reference, gives `plan-missing:`; a check each.

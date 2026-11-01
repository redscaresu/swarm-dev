---
kind: code
status: blocked
epic: board-loose-ends
depends_on: [lead-wait-timeout-line]
needs: [lead-wait-timeout-line (its edit of commands/swarm.md's wait --lead step; which this story's planned-line handling sits in; start from its merged text)]
touches: [bin/lib/lifecycle.sh:lead_queue (plan_lines call), bin/lib/lifecycle.sh:plan_lines (new), tests/plan_lines_test.sh (new), tests/lead_handler_test.sh:KINDS, docs/reference-lead.md:Plan swarm lines (§ The lead, new paragraph), commands/swarm.md:planned line handling (wait --lead step), skills/swarm-dev/SKILL.md:While it builds line list]
estimate_lines: 130
easy: false
---

# wait --lead prints `planned:` when a plan swarm's agents have all written their output (#762, part 1)

#762 (open): nothing tells the lead when a plan swarm's agents finish. On 2026-10-30 three plans finished at about 15:00, and the lead learned it from the user at 15:02 (incident 15:07:51Z). A planning tab's record, .swarm/state/scope-<epic> (plan-<hld> for /plan-hld), lists `<pane> <agent>` for each agent still open (e.g. scope-lead-woken: `w30:p3 critic`). Each agent writes .swarm/<epic>/<name>.json, with a .partial while it works (commands/plan-epic.md:30-33; bin/lib/agents.sh:754-768). <name> is the record name less a trailing -<epic>: survey-<epic> gives survey.json, critic gives critic.json, skeptic-<story> gives skeptic-<story>.json. An output counts only when it is valid JSON and newer than the attempt's base-rev, the planners' own resume rule (commands/plan-hld.md:94; commands/plan-epic.md:28): a malformed file or one from an earlier attempt does not. Add plan_lines, called from lead_queue. It takes each planning record that lists at least one agent and has no open plan board PR (plan_pr_open, bin/lib/board.sh:630-633). When every listed agent has its counted .json, it prints `planned: <epic> (<names> done), exit: /swarm-dev:plan-epic <epic>` (`/swarm-dev:plan-hld <hld>` for a plan- record). The line fires at each step's end too, since the lead starts the next step. Inputs are board and .swarm files: no gh, no new herdr read. It is an alert (not in LEAD_QUIET) and logs lead-woken like every other line. Add `planned` to tests/lead_handler_test.sh's KINDS (:16), the check that commands/swarm.md handles every line kind. Docs: a new `Plan swarm lines` paragraph in docs/reference-lead.md § The lead, the lead's handling in commands/swarm.md's wait --lead step, and the line list in skills/swarm-dev/SKILL.md (While it builds). The plan-missing: line is lead-wait-plan-missing-line's.

**Done when:**
- tests/plan_lines_test.sh (new: it needs scope records and .swarm/<epic> outputs, which wait_lead_test.sh's fixtures lack). A scope-e record lists survey-e and critic, both .json files exist and are valid, and there is no plan PR worktree. One poll prints `planned: e (survey, critic done), exit: /swarm-dev:plan-epic e` and logs lead-woken e.
- With the plan PR worktree present, with a .json older than the attempt's base-rev, or with a malformed .json, there is no planned: line; a check each. A plan-<hld> record gives the /swarm-dev:plan-hld exit.
- A planned: line prints on a run's first read (it is not quiet).
- Removing the plan_lines call from lead_queue (copy-aside proof) turns the first case red.
- tests/lead_handler_test.sh's KINDS has planned, and it passes. tests/doc_check_test.sh, tests/skill_test.sh, shellcheck and scripts/select-tests.sh --run pass.

---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: [reference-split]
---

# machine-usable

HLD Goal 11 (v0.31.0): the machine stays usable. The test cap weighs a selected run below a full one; finished panes close themselves (#690); builders push once and prove mutations on a copy after the PR opens (#695); and two flow readings print the bars.

**Done when:**
- stage: v0.31.0
- scripts/test.sh:210-320 counts a selected run as a fraction of a slot, the weight picked from .swarm/test-runs.tsv durations and named in the PR; a full run takes one; no, empty or 0 cap file still means no cap and nothing under ~/.swarm; a nested run takes none; tests/test_cap_test.sh and AGENTS.md's cap paragraph change in the same PR.
- A review pane closes in the merge or reconcile tail after its own merge (today merged_review board.sh:2385-2403 retires the pane that ran the merge to <name>-done and only tidy --yes closes it, contradiction 9) and after a handover note with merge = human (build.sh:773, 1376); a planning agent's pane closes once its output file is read (commands/plan-epic.md, plan-hld.md); a conductor's pane closes only after its Finish PR merged, never before (docs/lead-by-hand.md:51-56); a pane still working is left, with a line saying so.
- mutation_rule (build.sh:308-310) and AGENTS.md:184-188 say in the same PR: before the PR opens, break the fix in place with cp; after it opens, prove on a copy of the worktree without .git, never in place; push what is ready and put further points in the PR body; tests/fail_lines_test.sh:263-264's FAIL-line sentence stays; the conductor brief says a review that stopped on a moving head is rerun through its stopped: handling (lifecycle.sh:2762-2790, build.sh:1520).
- Readers for the bars: a `flow panes` section (new flow_panes.py) prints, per review agent, minutes from its story's merge or review event to the close of review-<slug> (close events, tidy's included) and the count over 30; `flow test_runs` gains a timeouts column counting reap events in the window (no flow section reads reap rows today; retro-report's retro arm will read the same events). docs/features.tsv rows: review panes open 30 minutes after their merge or handover (`flow panes`; bar 0), test-file timeouts per build (`flow test_runs: timeouts`; 2,050; bar under 100); docs/lead-by-hand.md entries for #690 (51-57) and #695 (82-89) removed.

**Out of scope:**
Makefile SLOW/SERIAL or .github/workflows/ci.yml shard changes (protected; only as its own lead-merged PR if a story must); flaky tests (flaky-tests); the corporate machine and the user's containers (HLD Non-goals).

**Constraints:**
- stage: v0.31.0. depends_on reference-split (it edits the reference files and AGENTS.md). Its flow_panes.py and flow_test_runs.py edits use telemetry-readers' helper (merged by then).
- rules.md rule 11 (rules-file-briefs) leaves where to break the fix to mutation_rule: change mutation_rule, not the rule.
- Pane closing goes through shut_agent, retire_agent and close_pane (lifecycle.sh:1735-1760) and tidy_panes.py (closes EMPTY and retired only); closing a conductor early kills its merge.
- tests/test_cap_test.sh's invariants (atomic slot rename, no cap when unset, nested takes none) stay; AGENTS.md's cap paragraph is the user's doc: edit it in the same PR and say so in the PR.
- Timing reads from test-runs.tsv happen once; load stays at or under 4 CPUs.

**Areas:** scripts/test.sh:cap (210-320), AGENTS.md:test-cap paragraph, AGENTS.md:184-188 (mutation proof), bin/lib/build.sh:mutation_rule, bin/lib/build.sh:conduct_brief (stopped rerun line), bin/lib/board.sh:merged_review, bin/lib/board.sh:reconcile tail, bin/lib/lifecycle.sh:close_pane, bin/lib/lifecycle.sh:tidy_panes, bin/lib/tidy_panes.py, bin/lib/flow_panes.py (new), bin/lib/flow_test_runs.py:timeouts column, commands/plan-epic.md:closing planning panes, commands/plan-hld.md:closing planning panes, docs/reference (Cleanup and Merging, in their split files), docs/lead-by-hand.md:#690 #695 and 51-56, docs/features.tsv:Goal 11 rows, tests/test_cap_test.sh, tests/reconcile_pull_test.sh, tests/close_test.sh, tests/close_exact_tab_test.sh, tests/agent_state_test.sh, tests/epic_briefs_test.sh, tests/fail_lines_test.sh, tests/flow_sections_test.sh, tests/flow_test_runs_test.sh

**Your part:**
- Decide the cap weight's default if the durations give no clear number (the plan proposes one).
- Merge by hand any PR that touches the Makefile or .github/.

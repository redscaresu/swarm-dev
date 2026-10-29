---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.30.0
depends_on: [telemetry-readers]
---

# telemetry-writers

HLD Goal 6, second half (v0.30.0): the nine fields as key=value tails, a fixed cause list on intervene, the flow sections that read each field, and a check that every features.tsv metric names a section that exists, so each of Goals 1 to 5 is read by one flow section and no pane.

**Done when:**
- stage: v0.30.0
- state= on every tell_agent refusal (agents.sh:1813-1837: none, gone, unknown, herdr:unknown, waiting:<what>, herdr:blocked, or the status text) and a `flow tell_refusals` section (new flow_tell_refusals.py): refusals by pane kind (an agent's pane per agents.tsv, or other) and state, and `could not reach` counts per target; Goal 2's rows (delivery-liveness) read it.
- slug= and role= on incident, reap, guard-blocked and merge-blocked lines: agents.sh incident sites (1190, 1555, 1573, 1642, 2445), lifecycle.sh (406, 446, 596), bin/swarm.sh's codex-limit (851) and codex reap (859), scripts/test.sh:102-105's reap line (slug from the run's branch story/<slug>; role builder; this writer produced all 2,069 reap rows in the repo's own log: contradiction 28), and the hooks' lines (hooks/merge-guard.sh:432-440, hooks/lead-stop.sh:72) in a story of their own that the lead merges (protected path).
- cause= on intervene: INTERVENE_CAUSES beside INTERVENE_KINDS (bin/swarm.sh:529-540), the fixed list review-rounds, false-stall, start-failed, gpg-locked, panes-open, story-gone, pr-no-story, dropped-lines, pr-churn, load-or-logs, no-conductor, flaky-test, classifier, upgrade, stuck-builder, red-main, reported-early, missing-review, tell-lost, other; `swarm.sh intervene <kind> <cause> "<line>"` validates it and dies listing the values; commands/swarm.md:656-658, docs/lead-by-hand.md:7 and tests/intervene_test.sh change in the same PR, hooks/user-caught-reminder.sh:23 in the hooks story; `flow incidents` counts by kind and cause (merge-mechanics' Goal 12 row reads the five merge causes).
- review events: round= and verdict= (pass, findings, decline-only, held) on review-agent and review-agent:next ok lines and on the `review` pass; a `review-finished <slug>` event written by `review --head` and by the handover; `pr-opened <slug> <url>` written at watch's opened line (merge.sh:2585; builders open PRs with a raw gh pr create, so no swarm.sh command runs at that moment: contradiction 27); `first-green <slug> <sha>` written at wait_pr's green exit (merge.sh:1945) once per PR; a `flow start_failures` section (new): review-agent did-not-start events and whether an ok start followed within 10 minutes (Goal 4's row); flow review_loops' end column reads verdict= when present (`flow_review_loops.py:verdict column`).
- stall inputs: the stalled incident (agents.sh:1555) and the escalate stalled event carry bg=0|1 test=0|1 sign=0|1 as the check read them; activity= on a wait-timeout (agents.sh:1577-1578) only when there is no progress (no commit and no session write since the wait began); `flow incidents` prints stalled incidents with their inputs, so Goal 3's bar reads as stalled incidents with any input 1 (must be 0) plus lead-hand and user-caught rows with cause=false-stall.
- version= (the installed plugin's version) on every event from append_event, the last writer to land; scripts/test.sh's reap line and the hooks' lines carry it too. flow lead_queue gains p90_min (today median and max only, flow_lead_queue.py:178: contradiction 34); flow test_runs resolves a run's slug from the branch column scripts/test.sh:161-175 writes (no new column). flow merges gains a holds-by-kind column (dropped-lines, protected, money) for Goal 8's row.
- tests/features_test.sh gains a check: every docs/features.tsv metric that names `flow <section>` names a flow_<section>.py that exists, and for the rows this HLD adds a column that section prints; the rows for Goals 2, 3, 4 (delivery-liveness), 5 (lead-woken) and 8 (merge-safety) pass it in this epic's spelling; Goal 6's own rows use event: uses of the new events. docs/reference.md's Flow section table maps each of Goals 1 to 5 to its one section.

**Out of scope:**
A sixth column; test-run start and end events; renaming outcome prefixes readers parse; flow_cost.py (rung-cost-block); a retro reader (retro-report); changing tell's delivery; the deferred, four-plus and review_wait columns (review-rounds-end).

**Constraints:**
- stage: v0.30.0. depends_on telemetry-readers only: its contract and scanner make every writer safe. Not for a patch (contradiction 21).
- Parallel with review-rounds-end, parts named so nothing clashes: bin/swarm.sh `review-finished event`, `pr-opened event`, `first-green event` here against its `decline-only event`; flow_review_loops.py `verdict column` here against its `deferred and four-plus columns`; tests/events_test.sh `field cases` here against its `decline-only cases`; flow_time_in_state.py is its alone.
- hooks/ is a protected path: one small story holds every hook edit (merge-guard.sh record, lead-stop.sh log, user-caught-reminder.sh's intervene line), held for the user by merge (board.sh:1559-1576, merge.sh:367-376). Board PR #543 (hooks keep the live events.tsv clean) touches the same lines: the lead merges or closes it first (lead_now).
- version= lands last, after the scanner and every reader have merged, or a row with it breaks a reader a sibling added meanwhile.
- A new flow section is a new flow_<name>.py (flow_report.py runs each) with its tests/flow_sections_test.sh entry; tests/events_test.sh's command list takes every new command; bash 3.2.
- Changing intervene's form is a change to what the lead runs: commands/swarm.md and docs/lead-by-hand.md change in the same PR, and the release PR names it.

**Areas:** bin/lib/agents.sh:append_event (version), bin/lib/agents.sh:tell_agent (state field), bin/lib/agents.sh:wait_agent (wait-timeout activity, stalled inputs), bin/lib/agents.sh:incident sites, bin/lib/lifecycle.sh:incident sites, bin/lib/lifecycle.sh:escalate stalled event, bin/swarm.sh:intervene (INTERVENE_CAUSES), bin/swarm.sh:codex-limit and reap events, bin/swarm.sh:review-finished event, bin/swarm.sh:pr-opened event, bin/swarm.sh:first-green event, bin/lib/merge.sh:watch opened line (pr-opened), bin/lib/merge.sh:wait_pr green exit (first-green), bin/lib/lifecycle.sh:review pass (round, verdict, review-finished), scripts/test.sh:reap line, hooks/merge-guard.sh:record, hooks/lead-stop.sh:log, hooks/user-caught-reminder.sh:intervene line, bin/lib/flow_tell_refusals.py (new), bin/lib/flow_start_failures.py (new), bin/lib/flow_review_loops.py:verdict column, bin/lib/flow_incidents.py, bin/lib/flow_lead_queue.py:p90_min, bin/lib/flow_merges.py:holds by kind, bin/lib/flow_test_runs.py:slug from branch, commands/swarm.md:intervene lines, docs/reference.md:Logs and outcomes, docs/reference.md:Flow and features (the goal-to-section table), docs/lead-by-hand.md:the intervene line (7), docs/features.tsv:Goal 6 rows, tests/events_test.sh:field cases, tests/flow_sections_test.sh, tests/features_test.sh (the section check), tests/incidents_test.sh, tests/intervene_test.sh, tests/flow_review_loops_test.sh, tests/merge_guard_test.sh

**Your part:**
- Merge by hand the one story PR that edits hooks/ (protected-path hold).
- Merge or close board PR #543 before this epic is planned.
- From the day the cause list lands, give a cause on every `swarm.sh intervene`.

---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [events-outcome-helper, events-fixture]
needs: [events-outcome-helper: events_outcome.outcome() / fields() and SEP (bin/lib/events_outcome.py), EVENT_SEP and the awk outcome(s) text EVENT_OUTCOME_AWK (bin/lib/agents.sh), events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output)]
touches: [bin/lib/flow_cost.py:events read, bin/lib/flow_features.py:events read, bin/lib/flow_holds.py:events read, bin/lib/flow_idle_slots.py:events read, bin/lib/flow_incidents.py:events read, bin/lib/flow_lead_queue.py:events reads, bin/lib/flow_merges.py:events read, bin/lib/flow_review_loops.py:events read, bin/lib/flow_throughput.py:events read, bin/lib/outcomes_join.py:events reads, bin/lib/outcomes_rows.py:events read, bin/lib/dataset.py:events read, bin/lib/touches_rows.py:ok_events, tests/events_tail_flow_test.sh (new)]
estimate_lines: 190
easy: false
---

# flow's, outcomes' and dataset's events readers read the outcome through the helper

Needs from events-outcome-helper: events_outcome.outcome(). Needs from events-fixture: the fixture, the tailed copy and same_output. Moves every events.tsv outcome read onto outcome(): flow_cost.py (:81-89; new since the epic, rung-cost-block #718), flow_features.py (:21), flow_holds.py (:58-70), flow_idle_slots.py (:99-154), flow_incidents.py (:28-39), flow_lead_queue.py (:125-268, WOKEN.get at :261), flow_merges.py (:8-10), flow_review_loops.py (:30-31), flow_throughput.py (:24-26), outcomes_join.py's events reads (:148-153, :210-222, incl. the `ok (` slice at :218-219; cost keys untouched), outcomes_rows.py (:93-163), dataset.py (:83-85), touches_rows.py (ok_events :89-96). Leave the files the epic listed that read no events outcome: ci_gate, dash_slow, herdr_events, flow_gh_calls, flow_run_times, flow_test_runs, panes, flow_time_in_state, flow_merge_ins, stall_py. flow's rows come from outcomes_rows and outcomes_join, so they move in the same PR. New tests/events_tail_flow_test.sh.

**Done when:**
- events_tail_flow_test.sh: with TZ=UTC and gh stubbed, `flow` (every section flow_report.py lists), `outcomes` and `dataset` print the same over the fixture project and its copy with `<SEP>k=v` on every row; holds, incidents, merges and lead_queue each print at least one data row untailed.
- An inline `reconcile <slug> ok (reopened)` row (no live log holds one) gives the same lead_queue with and without a tail.
- Putting one converted read back on a raw $5 / f[4] in a worktree copy without .git (AGENTS.md's mutation rule) turns the new test red; the PR names the read and keeps the FAIL line.
- Each event-dependent reader this story changes has a positive case: its output is non-empty and equal with and without a tail, adding synthetic rows where the fixture has none.

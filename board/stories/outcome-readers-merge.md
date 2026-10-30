---
kind: code
status: blocked
epic: telemetry-readers
depends_on: [events-outcome-helper, events-fixture]
needs: [events-outcome-helper: events_outcome.outcome() / fields() and SEP (bin/lib/events_outcome.py), EVENT_SEP and the awk outcome(s) text EVENT_OUTCOME_AWK (bin/lib/agents.sh), events-fixture: tests/fixtures/events/v029-sample.tsv and tests/events_tail_helpers.sh (a stand-in project from an events file, its tailed copy, same_output)]
touches: [bin/lib/merge.sh:base_merged, bin/lib/merge.sh:base_merged_from, bin/lib/merge.sh:dropped_lines (its base-merged read), bin/lib/merge.sh:report_collected, bin/lib/merge.sh:key_reds, bin/lib/merge.sh:red_mains, bin/lib/merge.sh:stacked_parents, bin/lib/board.sh:fix_main_owner, bin/lib/board.sh:merge_refused, bin/lib/board.sh:last_event, bin/lib/board.sh:reset_at, tests/events_tail_merge_test.sh (new)]
estimate_lines: 130
easy: false
risk: high
---

# merge.sh's and board.sh's events readers read the outcome through the helper

Needs from events-outcome-helper: EVENT_OUTCOME_AWK. Needs from events-fixture: the fixture, the tailed copy and same_output. Puts every events.tsv outcome read in merge.sh and board.sh on the awk outcome(): merge.sh base_merged (742), base_merged_from (748), dropped_lines' base-merged read (796), report_collected (1349), key_reds (1803-1804; its split($5) would take tail words), red_mains (1867-1870), stacked_parents (3014-3015; the substr slice); board.sh fix_main_owner (863), merge_refused (921-923), last_event (2246; returns the stripped outcome, so the `reconcile\tok (reopened)` compares at swarm.sh:557, board.sh:845 and 2238 hold), reset_at (2343). The epic named only base_merged here and no board.sh site. New tests/events_tail_merge_test.sh.

**Done when:**
- events_tail_merge_test.sh: over the fixture project and its tailed copy, plus inline `base-merged <sha>` and `base-merged <sha> from <sha>` merge rows (the cut has none), each function above gives the same result for every target (printed output for a text reader, exit status for a predicate); red_mains and stacked_parents are non-empty untailed.
- With a tailed `reconcile <slug> ok (reopened)` as a story's last row, `swarm.sh hold <slug> <why>` refuses as it does untailed.
- Putting one converted read back on a raw $5 / f[4] in a worktree copy without .git (AGENTS.md's mutation rule) turns the new test red; the PR names the read and keeps the FAIL line.
- For each reader this story changes: a text reader's output is non-empty and equal with and without a tail; a predicate (one that returns a status and prints nothing) gives the expected success and failure statuses, the same with and without a tail. Synthetic rows fill any case the fixture lacks.
- base_merged, merge_refused and report_collected are checked by exit status (success and failure cases), with and without a tail.

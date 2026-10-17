---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/outcomes_rows.py, bin/lib/outcomes_join.py, bin/lib/flow_time_in_state.py (new), docs/features.tsv:time-in-state row, tests/time_in_state_test.sh (new)]
easy: false
estimate_lines: 220
---

# outcomes splits a story's minutes into building, CI, review wait, fixing and merge wait; flow sums them per epic

Needs fold-reports' section loader (a new bin/lib/flow_time_in_state.py); edits bin/lib/outcomes_rows.py and outcomes_join.py. From events.tsv (start, review, tell:findings, merge), the PR's times and its check timings, five phases split each story's start-to-merge minutes: building, CI running, waiting for review, fixing findings, waiting for a merge (the lead's or the user's). Where two phases apply to the same minute, the higher one takes it: fixing > CI running > review wait > merge wait > building. They are five columns at the end of outcomes. flow sums them per epic, largest first. features.tsv row.

**Done when:**
- tests/time_in_state_test.sh: a fixture story whose CI runs while its review agent has started gets each of the five columns right by the precedence rule, the five sum to its start-to-merge minutes, and flow's epic line lists the largest first.

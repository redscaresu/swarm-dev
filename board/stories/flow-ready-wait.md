---
kind: code
status: ready
depends_on: []
touches: [bin/lib/report.py:PHASES, bin/lib/flow_time_in_state.py, tests/flow_test.sh]
easy: false
estimate_lines: 150
---

# flow measures how long a ready story waits for a builder, and how often a builder slot sits idle

time_in_state counts building, ci, review_wait, fixing and merge_wait (bin/lib/report.py:8). It does not count the time between a story going `ready` and its builder starting, which is where 2026-10-22's 8-minute wait on merge-ins-diff-errors went. Add a `ready_wait` phase: from the commit that set the story `ready` on main (or the merge that unblocked it) to its first build's start. Report it in time_in_state like the other phases, with its median and p90 per epic, so board-merge-tells-conductor can be judged before and after.

**Done when:**
- tests/flow_test.sh: a fixture story readied at T and built at T+8 min shows ready_wait 8 min. One that started building first and was readied later (it can't) is counted as 0, not negative.
- `swarm.sh flow` on this repo prints a ready_wait median and p90 for safer-faster-swarm, quoted in the PR.

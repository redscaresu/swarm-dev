---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [time-in-state]
touches: [bin/lib/flow_time_in_state.py, bin/lib/flow_epic_totals.py, tests/time_in_state_test.sh]
---

# time-in-state counts time held behind another story's files

On 2026-10-18 twelve ready stories waited for hours because their files overlapped open PRs, and
nothing showed it until the user asked. time-in-state splits a story's life into states; add
`held` (ready, buildable, not started while a conductor ran) and split review time into `ci`,
`review` and `fixing`. `flow --epic` rolls the states up per epic: total hours in each state and
the share of the epic's wall clock.

**Done when:**
- A fixture with a story ready for 3 h while its conductor ran, then built, shows `held 3h` for it and in the epic roll-up.
- A fixture PR with two review rounds shows its ci, review and fixing hours, which sum to its time in review.

---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/flow_epic_totals.py (new), tests/flow_totals_test.sh (new)]
easy: true
estimate_lines: 90
---

# flow sums cost per epic and reports the merged-in-main share beside the 55% baseline

Needs fold-reports' section loader: a new bin/lib/flow_epic_totals.py. For each epic, its total cost beside its start-to-PR and PR-to-merge minutes. Then a 'merged-in-main share' line, per epic and for the window: the share of PRs whose main_merges is above 0. outcomes already counts main_merges per PR from gh's commits (bin/swarm.sh:1249-1336), and flow prints it beside leaner-faster-swarm's 55% baseline. outcomes already prints each story's cost and minutes, so outcomes is unchanged.

**Done when:**
- tests/flow_totals_test.sh: a two-epic fixture whose outcomes rows hold known main_merges checks each epic's cost sum and minutes, each epic's merged-in-main share and the window's, and the 55% baseline beside them.

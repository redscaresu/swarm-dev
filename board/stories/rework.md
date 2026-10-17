---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/report.py:rework_of, bin/lib/outcomes_rows.py, bin/lib/outcomes_join.py, bin/lib/flow_reviewers.py, docs/features.tsv:rework row, tests/rework_test.sh (new)]
easy: false
estimate_lines: 150
---

# Rework counts against the first PR's story, model and reviewer

Needs fold-reports' bin/lib/flow_reviewers.py. Uses rework_of() in bin/lib/report.py (model-fit-table's definition; add it if your base lacks it). outcomes gets a rework column at the end, per story (outcomes_rows.py and outcomes_join.py). flow's reviewer rows count rework against each reviewer that reviewed the first PR. features.tsv row.

**Done when:**
- tests/rework_test.sh: a fixture with a PR fixed 3 days later by a PR naming it, one fixed 9 days later and one escaped finding checks the outcomes rework column and the reviewer rows.

---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/flow_ci_health.py (new), docs/features.tsv:ci-health row, tests/ci_health_test.sh (new)]
easy: false
estimate_lines: 150
---

# flow reports CI health: median minutes per PR head, red runs per PR, flakes

Needs fold-reports' section loader: a new bin/lib/flow_ci_health.py that calls gh itself for the window's PRs. Per project: the median CI minutes per PR head SHA, red runs per PR, and flakes (a red run then a green one on the same head SHA). A gh failure prints `ci health: gh failed` and no numbers, never zeros. features.tsv row.

**Done when:**
- tests/ci_health_test.sh: a gh stub with a flaky head, a red head fixed by a new head and a green PR checks the median, red runs per PR and flake count; a failing gh stub prints the failure line and no numbers.

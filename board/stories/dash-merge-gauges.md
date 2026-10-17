---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/dash_render.py, bin/lib/dash.sh:agent list, tests/fixtures/dash/golden-*.txt (regenerate if present), docs/dash.md:speedometer bullet, tests/dash_gauges_test.sh (new)]
easy: false
estimate_lines: 240
---

# dash draws a 14-day merge sparkline, a merge-rate gauge and a running-agents gauge

Builds on the split: the speedometer line in bin/lib/dash_render.py (PR #216), and dash's agent list in bin/lib/dash.sh, the one status uses. Under the speedometer line: a 14-day merges-per-day sparkline (▁▂▃▅▇) with today's count and the 7-day average marked. At 100 columns or more, a gauge of the 7-day rate against the best 7-day rate in events.tsv, and a gauge of agents running now (builders, conductors and review agents, a colour each) against the most at once in the last 7 days, with the count. Under 60 columns, the text line only. The running count ships with an agreement test against status, and dash-check adds it to --check. Regenerate golden frames if they are on your base.

**Done when:**
- tests/dash_gauges_test.sh: a 14-day fixture events.tsv draws the expected sparkline, today's count and 7-day average; at 100 columns both gauges show the right best rate and peak; at 59 columns only the text line shows; the running count equals status's agent count on the same fixture.

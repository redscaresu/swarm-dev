---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/dash_render.py, tests/fixtures/dash/two_projects.sh (new), tests/fixtures/dash/golden-*.txt (new), tests/dash_golden_test.sh (new), docs/dash.md:golden paragraph]
easy: false
estimate_lines: 200
---

# A two-project dash fixture, and golden frames at 60, 100 and 200 columns with a fixed clock

Builds on the split: bin/lib/dash_render.py takes its clock from SWARM_DASH_NOW when it is set. Add tests/fixtures/dash/two_projects.sh, a two-project fixture whose agents, costs, lead queues, needs-you items, epics, merges today and 7-day rates all differ; dash-check reuses it. Render it at 60, 100 and 200 columns into tests/fixtures/dash/golden-<cols>.txt. The test fails on any difference, and UPDATE_GOLDEN=1 rewrites the files. docs/dash.md says a change to dash commits its regenerated frames. The committed frames add about 150 more lines.

**Done when:**
- tests/dash_golden_test.sh passes, fails when one character of a golden file changes, and UPDATE_GOLDEN=1 rewrites all three files to match.
- Two runs a minute apart give identical frames.

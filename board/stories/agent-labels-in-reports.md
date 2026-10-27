---
kind: code
status: blocked
epic: workspace-labels
depends_on: [where-command, status-time-limit, dash-time-limit]
needs: [where-command: agent_where (bin/lib/agents.sh), status-time-limit: status_report as it leaves it (shared part), dash-time-limit: bin/lib/dash.sh:dash_render as it leaves it (shared part)]
touches: [bin/lib/merge.sh:status_report, bin/lib/dash.sh:dash_render, bin/lib/dash_render.py:agent rows, tests/agent_labels_test.sh (new)]
estimate_lines: 150
easy: false
---

# status and dash show each agent's workspace and tab

Uses where-command's agent_where, and status-time-limit's status_report and dash-time-limit's dash_render as they leave them (shared parts). status (status_report, bin/lib/merge.sh:1817+) and dash's agent rows (bin/lib/dash_render.py, fed by dash_render in bin/lib/dash.sh:578) print each agent's workspace label and tab beside its pane id, from herdr's lists read once per run within the report deadline.

**Done when:**
- tests/agent_labels_test.sh (new), herdr stubbed, two projects: status and dash name each agent's own workspace and tab labels; it fails with the labels dropped or read from the other project.
- tests/dash_test.sh and the dash --check test pass.

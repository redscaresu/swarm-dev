---
kind: code
status: blocked
epic: workspace-labels
depends_on: [conductor-workspace-label]
needs: [conductor-workspace-label: project_label, the Workspace labels list in docs/reference.md and README.md, and tests/workspace_labels_test.sh]
touches: [bin/swarm.sh:dispatch top, bin/lib/lifecycle.sh:lead_caller (new), tests/workspace_labels_test.sh:swarm-lead cases, docs/reference.md:Workspace labels, README.md:Workspace labels]
estimate_lines: 120
easy: false
risk: high
---

# The lead's workspace and tab are renamed swarm-lead · <project>

Uses conductor-workspace-label's project_label, its Workspace labels list and tests/workspace_labels_test.sh. On 2026-10-26 two workspaces were both `kanban` (the lead's takes its folder's name). Add lead_caller (bin/lib/lifecycle.sh, new): the caller is the lead, with no SWARM_AGENT or SWARM_GH_CALLER, as hooks/lead-session.sh's lead_project tells it (the hook does not change); lead-agents-workspace uses it too. At the top of dispatch (bin/swarm.sh), the first command run from the lead inside herdr renames that workspace and its tab `swarm-lead · <project label>` (herdr workspace rename, herdr tab rename) and records the workspace id under .swarm/lead/, so later commands send nothing; a command from an agent's pane renames nothing. A rename herdr refuses is said once and recorded, not retried every command. This runs on every command, hence risk: high: no herdr call when the record is there, and none without a reachable herdr (tests run with HERDR_SOCKET_PATH dropped, tests/test_helpers.sh).

**Done when:**
- tests/workspace_labels_test.sh gains cases, two projects: the first command from each lead's workspace renames it and its tab to its own label; a second command sends no rename; a command with SWARM_AGENT set renames nothing; a refused rename is said once. Each fails with the rename removed or run every time.
- A test runs a read-only command with the record present and finds no herdr call.

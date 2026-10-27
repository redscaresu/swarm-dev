---
kind: code
status: blocked
epic: workspace-labels
depends_on: [conductor-workspace-label, lead-workspace-rename]
needs: [conductor-workspace-label: epic_workspace's `<project label> · <label>` form, lead-workspace-rename: lead_caller, and the Workspace labels lines and test file as it leaves them (shared parts)]
touches: [bin/lib/agents.sh:next_pane, tests/workspace_labels_test.sh:lead-agents cases, docs/reference.md:Workspace labels, README.md:Workspace labels]
estimate_lines: 90
easy: true
---

# Agents the lead starts outside an epic open in <project> · lead-agents

Uses conductor-workspace-label's epic_workspace and lead-workspace-rename's lead_caller and Workspace labels lines (shared parts). next_pane (bin/lib/agents.sh:196-230) opens an agent's tab in the caller's HERDR_WORKSPACE_ID, so agents the lead starts (the HLD co-author, planners, a restarted builder: w20:p12 on 2026-10-26) land in the lead's own workspace. When lead_caller is true, open the tab in epic_workspace lead-agents, `<project label> · lead-agents`; a conductor's agents stay in its workspace. Close a new workspace's placeholder tab once the agent's tab is open, as start_conductor does (bin/lib/build.sh:1313-1316).

**Done when:**
- tests/workspace_labels_test.sh gains cases, two projects: `swarm.sh agent` from each lead opens its tab in that project's lead-agents workspace, never the lead's; from a conductor's environment it opens in the caller's workspace; close then closes the tab. Each fails with next_pane's old workspace choice.

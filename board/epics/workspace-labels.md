---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# Users can tell which workspace and tab is which

Lead, conductor and lead-agent workspaces carry project labels that stay distinct across swarms, and where, status, dash and swarms show them.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- conductor-workspace-label: Each conductor's workspace is labelled <project> · <epic>
- lead-workspace-rename: The lead's workspace and tab are renamed swarm-lead · <project>
- lead-agents-workspace: Agents the lead starts outside an epic open in <project> · lead-agents
- where-command: swarm.sh where <agent> prints the agent's workspace and tab
- agent-labels-in-reports: status and dash show each agent's workspace and tab
- swarms-command: swarm.sh swarms lists every swarm running on the machine

**Areas:** see each story's touches.

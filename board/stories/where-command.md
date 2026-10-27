---
kind: code
status: blocked
epic: workspace-labels
depends_on: [report-run-times]
needs: [report-run-times: the READ_ONLY_COMMANDS list and its comment as it leaves them (shared part)]
touches: [bin/swarm.sh:usage header, bin/swarm.sh:where dispatch arm, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/agents.sh:agent_where (new), tests/where_test.sh (new), docs/reference.md:where command row, README.md:where command line]
estimate_lines: 120
easy: false
---

# swarm.sh where <agent> prints the agent's workspace and tab

Uses report-run-times' READ_ONLY_COMMANDS lines as it leaves them (shared part). New read-only command `swarm.sh where <agent>` (a slug, review-<slug>, conduct-<epic> or a herdr agent name): the agent's pane id, its workspace's label and its tab's label, from one herdr agent list plus the workspace and tab lists; an agent herdr does not list in this project's panes prints so and exits 1. Add it to READ_ONLY_COMMANDS, the usage header and a dispatch arm (bin/swarm.sh), docs/reference.md's commands table and README.md's command list. Put the lookup in agent_where (bin/lib/agents.sh, new) for agent-labels-in-reports.

**Done when:**
- tests/where_test.sh (new), herdr stubbed, two projects whose agents share a slug: `where <slug>` in each prints its own workspace and tab labels; an unknown agent exits 1. It fails if where reads the other project's agent.
- tests/command_names_test.sh and tests/doc_check_test.sh pass.

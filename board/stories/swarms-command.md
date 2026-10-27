---
kind: code
status: blocked
epic: workspace-labels
depends_on: [conductor-workspace-label, lead-workspace-rename, where-command]
needs: [conductor-workspace-label: project_label and the conductor workspace labels, lead-workspace-rename: the `swarm-lead · <project label>` label, where-command: bin/swarm.sh's usage header and READ_ONLY_COMMANDS as it leaves them (shared parts)]
touches: [bin/swarm.sh:usage header, bin/swarm.sh:swarms dispatch arm, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/dash.sh:swarms (new), tests/swarms_test.sh (new), docs/reference.md:swarms command row, README.md:swarms command line]
estimate_lines: 160
easy: false
---

# swarm.sh swarms lists every swarm running on the machine

Uses conductor-workspace-label's project_label and `<project label> · <epic>` labels, lead-workspace-rename's `swarm-lead · <project label>` label, and where-command's usage header and READ_ONLY_COMMANDS lines (shared parts). New read-only command `swarm.sh swarms` (the epic offers `dash --all` or `swarms`; swarms leaves dash's flags as they are): from herdr's workspace list and one agent list, each swarm-lead workspace as a project with a lead, and under it that project's other workspaces with their agents. A workspace belongs to a project by its label and its cwd, never by a prefix of another project's name or a shared basename.

**Done when:**
- tests/swarms_test.sh (new), herdr stubbed: two projects where one name is a prefix of the other (app, app-2), and two with one basename (/a/app, /b/app): swarms lists each lead with only its own conductors and agents. It fails with prefix or basename matching.
- tests/command_names_test.sh and tests/doc_check_test.sh pass.

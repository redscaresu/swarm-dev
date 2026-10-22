---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [upgrade-until-done]
touches: [bin/lib/merge.sh:merge --release, tests/merge_test.sh, docs/reference.md:Releases, AGENTS.md]
easy: true
estimate_lines: 90
---

# A release updates the installed plugin and moves every running agent onto it

After v0.25.0 merged on 2026-10-22, the lead ran `claude plugin marketplace update`, `claude plugin update` and `swarm.sh upgrade` by hand, and had to ask the user to restart the lead session. Running agents stayed on 0.24.0, without #347's GitHub budget fix, for hours.

Needs upgrade-until-done's detached `swarm.sh upgrade`. Once `swarm.sh merge --release` has confirmed the tag and the GitHub release, it runs `claude plugin marketplace update <marketplace>` and `claude plugin update <plugin>@<marketplace>`, but only when the release is this plugin's own repo. It checks that the new version's directory exists, then starts the new version's `swarm.sh upgrade` (detached) in every project with running agents, or in this project when it can't tell which. It prints the upgrade's log path, and one line asking the user to restart the lead session (`/exit`, then `claude --continue`), since Claude Code loads a plugin's hooks only at startup. If the update or the upgrade fails, it says so, the release still counts as done, and the exit code stays 0.

**Done when:**
- tests/merge_test.sh, with stub gh, claude and swarm.sh: a `--release` merge of the plugin's own repo, after a confirmed tag and release, runs the two update commands and then the new version's `upgrade`, and prints the restart line. A failed `plugin update` warns and runs no upgrade. A release of another repo runs neither.
- docs/reference.md § Releases and AGENTS.md's release steps say the release updates the plugin and upgrades the agents, and that the lead session is restarted by the user.

---
kind: chore
status: blocked
blocked_by: [board-readme-sync-test, tell-conductor-note, merge-command, codex-bump-not-a-finding, story-warns-cross-epic-touches, flow-speedups-release]
epic: lead-loop
depends_on: [board-readme-sync-test, tell-conductor-note, merge-command, codex-bump-not-a-finding, story-warns-cross-epic-touches, flow-speedups-release]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the lead-loop release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base (after flow-speedups-release), not a hardcoded number. The PR body lists what ships: tell note and the conductor inbox, swarm.sh merge with its main-CI wait and merge_admin (off), story's cross-epic touches warning and --strict, the version-bump review line, and the stories README sync test. No README change. The lead merges; release.yml publishes v<version>.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- git log since the previous bump on main holds the merges of every lead-loop code story; if not, the PR names the release that carried them (flow-speedups-release carries merge-command if it merged first).
- `claude plugin validate .` and every tests/*_test.sh pass, and the PR says humanizer ran over its description.

---
kind: chore
status: blocked
blocked_by: [codex-time-limit, story-after-unmerged-close, wait-until-report, reconcile-keeps-board-edits, merge-agent-ready, board-pr-review-once, goal-for-builders-release]
epic: flow-speedups
depends_on: [codex-time-limit, story-after-unmerged-close, wait-until-report, reconcile-keeps-board-edits, merge-agent-ready, board-pr-review-once, goal-for-builders-release]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the flow-speedups release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base (after goal-for-builders-release), not a hardcoded number. The PR body lists what ships: codex-review with its 10-minute limit, reconcile's cleanup and kept board edits, wait --until-report, the merge = agent rules and guard (off until a project sets it), and the board-PR review line. No README change. The lead merges, and release.yml publishes v<version>.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- git log since the previous bump on main holds the merges of every flow-speedups code and docs story. If not, the PR names the release that carried them.
- `claude plugin validate .` and every tests/*_test.sh pass, and the PR says humanizer ran over its description.

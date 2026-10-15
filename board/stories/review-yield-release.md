---
kind: chore
status: blocked
blocked_by: [finding-reviewer-column, briefs-name-the-reviewer, review-yield-report, lead-loop-release]
epic: review-yield
depends_on: [finding-reviewer-column, briefs-name-the-reviewer, review-yield-report, lead-loop-release]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the review-yield release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base (after lead-loop-release), not a hardcoded number. The PR body lists what ships: the findings reviewer column and `log-finding --reviewer`, the conductor rule that names the reviewer, and `swarm.sh review-yield`. No README change. The lead merges; release.yml publishes v<version>.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- git log since the previous bump on main holds the merges of finding-reviewer-column, briefs-name-the-reviewer and review-yield-report; if not, the PR names the release that carried them.
- `claude plugin validate .` and every tests/*_test.sh pass, and the PR says humanizer ran over its description.

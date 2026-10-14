---
kind: chore
status: blocked
blocked_by: [escalate-live-check, every-role-reachable-test]
epic: fable-on-call
depends_on: [escalate-live-check, every-role-reachable-test]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the fable-on-call release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base; do not hardcode it (0.14.0 today; cold-start-release may bump first). The PR body lists what ships: escalate_after, attempts:, reset, the ladder counts, the give-up rule. No README change. The user merges; release.yml publishes v<version>.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- git log since the previous bump on main holds the merges of every fable-on-call code story; otherwise the PR says which release carried them.
- `claude plugin validate .` and every tests/*_test.sh pass; the PR says humanizer ran over its description.

**From review (binding; overrides the scope above where they differ):**
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

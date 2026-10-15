---
kind: chore
status: blocked
blocked_by: [dash-no-board, dash-watch-reexec, dash-escalation, dash-state-age-and-findings, dash-lead-queue, dash-codex-row]
epic: dash-tells-the-truth
depends_on: [dash-no-board, dash-watch-reexec, dash-escalation, dash-state-age-and-findings, dash-lead-queue, dash-codex-row]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the dash-tells-the-truth release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base (flow-speedups-release and goal-for-builders-release bump the same line), not a hardcoded number. The PR body lists what ships: no-board message, watch re-exec, Fable on call, state ages, grouped findings, the lead key (off until a project sets it), the codex row. No README change. release.yml publishes v<version> on merge.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json and its version is greater than main's at the PR's base. git log since the previous bump on main holds the merges of all six dash-tells-the-truth code stories; any it does not hold, the PR names the release that carried it. `claude plugin validate .` and every tests/*_test.sh pass, and the PR says humanizer ran over its description.

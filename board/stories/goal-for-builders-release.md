---
kind: chore
status: blocked
blocked_by: [goal-spike, fable-on-call-release, goal-condition, goal-delivery, goal-done-when-line, close-takes-a-cause, goal-wait-no-nudge, goal-on-findings, goal-conductor-rule]
epic: goal-for-builders
depends_on: [goal-spike, fable-on-call-release, goal-condition, goal-delivery, goal-done-when-line, close-takes-a-cause, goal-wait-no-nudge, goal-on-findings, goal-conductor-rule]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the goal-for-builders release

Bump `version` in .claude-plugin/plugin.json to the next minor of whatever main holds at the PR's base (after fable-on-call-release's bump); do not hardcode it. The PR body lists what ships: the goal setting (off), the goal condition and its delivery after the brief, close causes, no nudge for a builder with a goal, a fresh goal on findings, the conductor's cause rule and the Done when line. No README change. The user merges; release.yml publishes v<version>.

**Done when:**
- The diff is one line in .claude-plugin/plugin.json, and its version is greater than main's at the PR's base.
- git log since the previous bump on main holds the merges of every goal-for-builders code and docs story; otherwise the PR says which release carried them.
- `claude plugin validate .` and every tests/*_test.sh pass; the PR says humanizer ran over its description.

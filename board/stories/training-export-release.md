---
kind: chore
status: blocked
blocked_by: [cost-since, outcomes-every-attempt, outcomes-attempt-events, outcomes-story-columns, export-command, training-export-counts, session-log-reads-archive]
epic: training-export
depends_on: [cost-since, outcomes-every-attempt, outcomes-attempt-events, outcomes-story-columns, export-command, training-export-counts, session-log-reads-archive]
touches: [.claude-plugin/plugin.json]
---

# Bump plugin.json once for the training-export release

Bump `version` in .claude-plugin/plugin.json once (minor: a new command); merging it publishes the release and tag (.github/workflows/release.yml, AGENTS.md).

**Done when:**
- plugin.json's version is greater than main's at branch time, and the PR changes no other file.
- `claude plugin validate .`, shellcheck and every tests/*_test.sh pass.

**From review (binding; overrides the scope above where they differ):**
- Depends on session-log-reads-archive.

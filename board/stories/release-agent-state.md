---
kind: chore
status: blocked
blocked_by: [docs-refresh-0-14, render-flow-diagram]
epic: agent-state-from-the-session
depends_on: [require-claude, no-herdr-state-for-claude-sessions, docs-refresh-0-14, render-flow-diagram]
touches: [.claude-plugin/plugin.json, README.md, docs/, commands/, bin/swarm.sh (comments only, for stale-wording hits)]
---

# Bump plugin.json to 0.14.0 for the agent-state release

Bump the version in .claude-plugin/plugin.json from 0.13.0 to 0.14.0; it is the only manifest that carries a version. First, grep README.md, AGENTS.md, docs/, commands/ and bin/swarm.sh comments for old wording: 'herdr shows working', 'API error', '`tell <slug> <file>`', and 'blocked on a prompt' for Claude agents. Fix any hit in this PR (an AGENTS.md hit is handed to the lead, who edits it alone). The user merges the PR (merge = human), and that publishes v0.14.0 through release.yml.

**Done when:** plugin.json says 0.14.0, `claude plugin validate .` passes, CI is green on the head, and the grep finds no old wording.

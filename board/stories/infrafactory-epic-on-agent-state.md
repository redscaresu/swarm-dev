---
kind: lead
status: blocked
blocked_by: [release-agent-state]
epic: agent-state-from-the-session
depends_on: [release-agent-state]
touches: []
---

# Run one infrafactory epic on 0.14.0, then say go for fable-on-call

Starts after the release merges. **You:** run `claude plugin update swarm-dev@swarm-dev`, restart Claude Code, and run `/swarm` on infrafactory for one epic. The lead then reads infrafactory's .swarm/agents.tsv and events.tsv for that run, and posts on this story the session coverage, the `nudge` count and the tell counts by kind (the goal-off baseline). **You:** say go before fable-on-call starts, or name what went wrong; anything wrong becomes a new story.

**Done when:** Every Claude agent's agents.tsv line from the run carries a session id; codex lines keep '-'. The run's nudge and tell-kind counts are posted on the story. The user's go for fable-on-call is recorded on the story.

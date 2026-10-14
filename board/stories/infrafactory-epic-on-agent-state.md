---
kind: lead
status: ready
epic: agent-state-from-the-session
depends_on: [release-agent-state]
touches: []
---

# Run one infrafactory epic on 0.14.0, then say go for fable-on-call

Starts after the release merges. **You:** run `claude plugin update swarm-dev@swarm-dev`, restart Claude Code, and run `/swarm` on infrafactory for one epic. The lead then reads infrafactory's .swarm/agents.tsv and events.tsv for that run, and posts on this story the session coverage, the `nudge` count and the tell counts by kind (the goal-off baseline). **You:** say go before fable-on-call starts, or name what went wrong; anything wrong becomes a new story.

**Done when:** Every Claude agent's agents.tsv line from the run carries a session id; codex lines keep '-'. The run's nudge and tell-kind counts are posted on the story. The user's go for fable-on-call is recorded on the story.

## Baseline (goal off): infrafactory rehearsal-walls, 2026-10-14

The run is infrafactory's rehearsal-walls epic: 13 stories, #555 to #567, 08:53 to 23:00 UTC on 2026-10-14. It began on 0.14.0, and 0.15.0 (the same agent-state reader) was installed at 13:15. The counts come from infrafactory's .swarm/agents.tsv and events.tsv, lines whose name matches `rehearsal-walls`.

- Session coverage: every one of the 20 Claude agent lines has a session id (18 Opus, 2 Sonnet). There are no codex lines, because codex ran as `codex exec review` inside the conductors, not as an agent.
- `nudge`: 3. One went to rehearsal-walls-regate and two to rehearsal-walls-prepare-e2e, all from `wait`.
- Tells by kind: `findings` 17, `resume` 3, `nudge` 0. Two of the resumes went to rehearsal-walls-fakeaws-pin after a disk-full prompt, and one went to the conductor.
- Not counted: the lead's `herdr agent prompt` messages to a busy conductor (merge notices and the codex fix) bypass `tell`, so they are not in events.tsv.

The user's go for fable-on-call was given on 2026-10-14 at about 13:30 and widened at about 20:45 to all remaining board work: "all of this work is approved. once you are ready to implement use swarm-dev to do so".

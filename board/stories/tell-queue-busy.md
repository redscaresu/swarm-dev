---
kind: code
status: blocked
epic: board-pr-and-briefs
depends_on: [tell-reads-blocked-pane]
needs: [tell-reads-blocked-pane: the pane check in bin/lib/agents.sh:tell_agent]
touches: [bin/lib/agents.sh:tell_agent busy arm, bin/lib/agents.sh:tell_queue (new), docs/reference.md:tell busy line, tests/tell_queue_test.sh (new)]
estimate_lines: 200
easy: false
risk: high
---

# A tell to a busy agent is queued and delivered when its turn ends, never lost

On 2026-10-27 a patch story's review findings never reached its builder: the conductor's `tell findings` at 09:45 was refused because herdr listed the builder as working (it sat at its prompt with a background test shell), nothing retried, and the builder waited over an hour (v0.29.0 build; user, 2026-10-27). Several nudges that night were refused the same way. Notes to a conductor already queue and wake it when its turn ends (note_wake, bin/lib/agents.sh:1521); findings, nudge and resume tells to any other agent do not.

Change tell_agent's refusal for a busy agent into a queue: the message is stored under .swarm/ for that agent, the command prints `queued: <agent> (busy); delivered when its turn ends` and exits 0, and the queued message is sent when the agent is next idle, through the same once-a-minute wake that notes use. Findings keep their round count at delivery, not at queueing, so a queued findings tell never counts twice. A newer findings tell for the same story replaces a queued one that was not sent. Merge after tell-reads-blocked-pane (both edit tell_agent).

**Done when:**
- A test: a findings tell to an agent herdr lists as working is queued, not refused; when the agent goes idle it is delivered once, and the round count rises once.
- A test: two findings tells queued for one busy builder deliver only the newer one.
- A test: a queued tell to an agent that has gone (closed pane) is dropped with a line the lead sees, not delivered to another pane.
- docs/reference.md's tell entry says a busy agent's tell is queued.
- `make test` passes.

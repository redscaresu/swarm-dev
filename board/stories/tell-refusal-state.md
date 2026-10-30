---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/swarm.sh:event_fields (new, beside die), bin/swarm.sh:main (logging tail: EV_FIELDS and the fields file), bin/lib/agents.sh:tell_agent (state case refusals), bin/lib/agents.sh:tell_gone, tests/tell_blocked_test.sh:state field cases, docs/reference-logs.md:tell sentence (Logs and outcomes)]
estimate_lines: 170
easy: false
---

# tell refusals log state=, through one event-fields channel main reads

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). Adds the one channel for fields a command learns while it runs (survey: main logs tell's refusal from DIE_FILE, swarm.sh:70-77, 1092-1109): `event_fields <key=value>...` beside die in bin/swarm.sh writes to a file beside DIE_FILE at main's level only (die's DIE_LEVEL rule), and an arm in main may set EV_FIELDS before dispatch; main's record_event calls at the end of main append both. tell_agent's state case (agents.sh:1940-1950) and tell_gone (agents.sh:1856-1868) call it before each die: state=none (no agent this project started holds the name), gone, unknown, herdr:unknown, waiting:<what>, herdr:blocked, or the status text of a `could not reach` refusal, made safe as the contract says for a value. Refusals made before tell_state runs (a bad kind, a missing file, herdr could not list agents) and the queue-lock refusal carry no state=: no state was read. queued:/replaced: lines are unchanged. review-event-fields reuses the channel.

**Done when:**
- tests/tell_blocked_test.sh state cases: a tell refused as gone, unknown, herdr:unknown, waiting:<what>, herdr:blocked, no agent holding the name, and an unknown status each writes one tell:<kind> line whose fields() give that exact state= value.
- Each refused line's outcome() is the die's first line, as before this change.
- A tell refused because herdr could not list agents, a delivered tell and a queued tell carry no state= field.
- An EV_FIELDS set by an arm and an event_fields call both reach the logged line; event_fields called inside a nested $(...) writes nothing.
- Copy-aside proof: removing the event_fields call from tell_gone turns the gone case red.
- docs/reference-logs.md's tell sentence names state= and its values; shellcheck and tests/doc_check_test.sh pass.

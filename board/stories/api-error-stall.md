---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh, tests/]
---

# A session stopped on an API error is seen as stopped

On 2026-10-18 conduct-safer-faster-swarm stopped at 10:21 on "API Error: Connection dropped
(ECONNRESET)" with two background shells still open. For over an hour nothing noticed:
`session_state` read `busy` (the open shells), so `wait --until-report` kept waiting, `next` said
"wait", and `tell` refused ("is still working") although herdr showed the agent `done`. The lead
had to type into the pane with `herdr pane run`.

When herdr says `done` or `idle` and the pane's last turn ended on an `API Error:` line, `wait`
returns `stalled: api error` at once, and `tell` delivers instead of refusing (the open shells do
not make the session busy). `next` names the stall.

**Done when:**
- A test with a fixture pane ending on an `API Error:` line, a session state of busy and herdr `done` makes `wait` print `stalled: api error` and `tell` deliver.
- The same fixture without the `API Error:` line still makes `tell` refuse.

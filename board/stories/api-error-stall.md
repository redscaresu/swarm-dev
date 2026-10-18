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

An API error is transient, so `wait` also resumes it by itself: it delivers "Your last turn
stopped on an API error; carry on where you stopped." and keeps waiting, at most 3 times in a row
for one agent (a turn that ends normally resets the count), then returns `stalled: api error` for
the lead.

For stops nobody has seen yet, `wait` also returns `stalled: no output for <N>m (<pane>)` when an
agent herdr calls working, or a session read as busy, has not changed its pane for
`stall_minutes` (default 20; a config key). It never nudges on that one: the lead reads the pane.

**Done when:**
- A test with a fixture pane ending on an `API Error:` line, a session state of busy and herdr `done` makes `wait` print `stalled: api error` and `tell` deliver.
- With the fixture, `wait` delivers the resume message and keeps waiting; on the fourth API-error stop in a row it returns `stalled: api error` without a fourth resume.
- A fixture pane unchanged for longer than `stall_minutes` makes `wait` return `stalled: no output`, naming the pane, and sends nothing.
- The same fixture without the `API Error:` line still makes `tell` refuse.

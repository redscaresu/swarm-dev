---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [idle-capacity]
touches: [bin/lib/board.sh:next_step, commands/swarm.md, tests/next_test.sh]
---

# An idle project plans its next unblocked epic without being asked

On 2026-10-18 infrafactory sat idle for hours with `next` printing `gate`, although the `later`
epic aws-web-stack-load-balancer had only one dependency, done since 2026-10-10. Planning is free
(read-only agents), and its plan still goes to the user for approval, so nothing needed the user
until then; the user had to ask "is there more work?".

When a project has no buildable story and no conductor running, `next` prints
`plan-epic <epic>` for the oldest `later` or `active` epic whose `depends_on` epics are all done,
with why ("its dependencies are done; planning costs nothing, the plan waits for approval"), before
it falls back to `gate`. commands/swarm.md: the lead runs it without asking; the approval of the
resulting stories stays the user's unless the epic is on a pre-approved list.

**Done when:**
- Fixture: no buildable story, a `later` epic whose one dependency is done; `next` prints `plan-epic <that epic>`. With the dependency not done, `next` prints `gate`.
- commands/swarm.md says the lead runs it unasked, and a test greps it.

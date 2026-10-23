---
kind: code
status: ready
depends_on: []
touches: [bin/lib/build.sh:send_goal, tests/goal_test.sh]
easy: true
estimate_lines: 50
---

# send_goal sends the /goal when the builder's first turn has already finished

The backlog conductor logged this out of scope on #374 (2026-10-23). send_goal (bin/lib/build.sh:355) waits for the session to read busy after the brief, and dies with "its session did not read busy within Ns ... so no /goal was sent" (line 365). Since #374, deliver_prompt can return after a short first turn has already ended and the session reads idle again. The brief was taken, but send_goal reads idle as "never started" and dies, so the builder runs with no goal. Treat a session that is idle after the brief as having taken it: check the session log for an assistant entry after the brief, the way deliver_prompt now does, and send the /goal.

**Done when:**
- tests/goal_test.sh (or the existing goal tests), with stubs: a session that turns busy and back to idle before send_goal reads it, with an assistant entry after the brief in its log, gets the /goal. One with no entry after the brief still fails as today.

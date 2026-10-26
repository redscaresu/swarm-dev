---
kind: code
status: ready
epic: board-pr-and-briefs
depends_on: []
touches: [bin/lib/agents.sh:wait_agent, docs/reference.md:wait-timeout incident line, tests/incidents_test.sh:wait-timeout cases]
estimate_lines: 45
easy: true
---

# A wait that times out on a working agent logs no incident

wait_agent logs `incident <name> wait-timeout: <status>` whenever its wait runs out (bin/lib/agents.sh:1405): 78 `wait-timeout: busy` lines in this project's .swarm/events.tsv since 2026-10-25. Log none when the status is either working value, busy or herdr:working (tell_agent's case, agents.sh:1641); keep the line for every other status. Make wait_agent's header (agents.sh:1375-1377) and docs/reference.md's wait-timeout line (:1213) match.

**Done when:**
- A test (tests/incidents_test.sh or the wait test that covers wait-timeout) times out a wait on a stub agent reporting busy and on one reporting herdr:working, and finds no wait-timeout line for either; one timing out on another status (e.g. blocked) still writes its line. The first two fail with the fix removed.

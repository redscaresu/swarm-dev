---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:review_agent, tests/review_agent_test.sh]
easy: true
estimate_lines: 50
---

# review-agent never puts back the last review's findings when the new review agent is running

Found by the backlog conductor on 2026-10-22. About eight times, `swarm.sh review-agent` printed "the brief was not taken up after 2 attempts (status 'none')" and "did not start", while the review agent was running with its brief. On that path, build.sh (around :572) moves the previous `${out}.prev` back to `${out}`, so `wait review-<slug>` returns at once on the old findings, and a conductor can act on a review of an earlier head. #374 stops the false "not taken up" in most cases, but this path stays wrong whenever the start really is ambiguous.

When start_agent fails, check whether the review agent exists, the way agent_field reads its pane. If it does, keep the old file aside (not back in place), say the start was unclear and the agent is running, and exit 0. Restore the old file only when no agent exists. Write the new head to `${out%.md}.head` in both cases where an agent runs. `wait review-<slug>` already waits for a findings file newer than the brief.

**Done when:**
- tests/review_agent_test.sh, with a stub start_agent that fails while the agent's pane exists: the old findings file is not back at `${out}`, the exit is 0, and the message says the agent is running. With no pane, the old file is restored and the exit is non-zero, as today.

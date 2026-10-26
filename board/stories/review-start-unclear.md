---
kind: code
status: ready
epic: no-agent-alert
depends_on: []
touches: [bin/lib/agents.sh:deliver_prompt start reading, bin/lib/build.sh:review_start_failed, tests/agent_liveness_test.sh:review start cases, tests/review_agent_test.sh:unclear start]
estimate_lines: 90
easy: true
---

# A review agent that took its brief is not read as an unclear start

This is small-fixes-027.md:14, whose touches name agents.sh:start reading (:5). herdr reports a review agent's start as 'unclear' while the agent runs and writes its review. deliver_prompt (bin/lib/agents.sh:732-771) dies 'may or may not have the brief' when it sees no turn start. review_start_failed (bin/lib/build.sh:628-655) then dies on `yes:*` for a state it does not take as running. A review agent sits idle while its codex runs (build.sh:579-582). Find the misread in the start reading and fix it, so an agent whose session took the brief (session_took, agents.sh:873-878) counts as started. Keep #464's rule: a brief that was not taken up is still a failure. A false failed start would make no-agent-review-gone's alert fire.

**Done when:**
- tests/agent_liveness_test.sh: a review agent whose session took the brief, while herdr reads it idle or unclear, counts as started. This case fails on the old code. One that never took the brief still fails.
- tests/review_agent_test.sh: for that agent, review-agent writes .swarm/reviews/<slug>.head and returns 0. It still dies for a start herdr surely did not send.

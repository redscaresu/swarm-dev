---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/agents.sh, tests/wait_test.sh]
estimate_lines: 40
easy: true
---

# wait logs an API-error resume as `resume`, not `nudge`

`wait` sends API_RESUME_MSG to an agent whose turn stopped on an API error and logs it as a nudge (bin/lib/agents.sh, the comment above wait_agent and resume_agent). A nudge means the builder stopped short of its work; an API-error resume means the API failed. Counting both as nudges inflates `flow`'s nudge count, and goal-for-builders (shipped in 0.17.0) wanted resume counted apart from nudge.

Log the API-error resume under the `resume` kind that `tell` already uses (is_tell_kind), and change the comment to match. The `stuck: api error` limit (API_RESUMES) keeps counting the same way.

**Done when:**
- A wait test whose stub pane stops on an API error once and then finishes finds a `resume` line, and no `nudge` line, for that agent in events.tsv.
- `flow`'s nudge count for that run is 0. `make test` passes.

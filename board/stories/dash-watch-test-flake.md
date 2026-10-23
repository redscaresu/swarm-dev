---
kind: code
status: ready
depends_on: []
touches: [tests/dash_watch_test.sh]
estimate_lines: 40
easy: true
---

# tests/dash_watch_test.sh passes every time

It flaked on 3 CI runs on 2026-10-23, after v0.26.0, for example https://github.com/redscaresu/swarm-dev/actions/runs/39879081962/attempts/1 (`swarm.sh flow`, ci_health). Read the failed runs' logs, find the timing or ordering the test assumes, and make it wait on the condition, not a sleep.

**Done when:**
- The cause is named in the PR, from the failed runs' logs.
- `for i in $(seq 30); do bash tests/dash_watch_test.sh || exit 1; done` passes under the CPU load of a full `make test` running beside it.

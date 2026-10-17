---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:start_conductor and conduct_epic, bin/lib/agents.sh:the name-held refusal, docs/reference.md:conduct --backlog, tests/conduct_backlog_test.sh]
easy: false
estimate_lines: 60
---

# Two projects can each run a backlog conductor at once

herdr agent names are global across projects, and every project's backlog conductor is named
`conduct-backlog` (bin/lib/build.sh:927-950). On 2026-10-17, infrafactory's backlog conductor was
running, so swarm-dev's `conduct --backlog` refused with "an agent this project did not start ...
holds this name" (bin/lib/agents.sh:673). The lead built swarm-dev's one-off by hand instead, which
loses a conductor's review loop and is one less build running.

Name the backlog conductor per project, e.g. `conduct-backlog-<project dir basename>` cut to
`agent_name`'s 32 characters. Keep it one name per project: `wait`, `close`, `next`, `dash` and the
report path must all find it by that name. `next` must still print a step the lead can run
(`conduct --backlog`, and `wait <the name>`). An epic slug that matches another project's epic has
the same clash. Leave that alone, but make the refusal say which project holds the name when
herdr shows it.

**Done when:**
- A test with two project dirs under one stubbed herdr starts both backlog conductors, and each gets its own name, brief and report.
- `next`, `wait`, `close` and `status` in each project find that project's backlog conductor and not the other's (asserted in the test).
- The name-held refusal names the other project when herdr's agent list gives its cwd (asserted in the test).

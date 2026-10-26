---
kind: code
status: ready
depends_on: []
touches: [hooks/merge-guard.sh:record, hooks/lead-stop.sh:log, tests/live_logs_test.sh:hook cases]
estimate_lines: 80
easy: true
---

# The plugin's hooks never write a project's live events.tsv from a test

tests-keep-live-logs-clean (#529) makes swarm.sh refuse to touch the main checkout's live `.swarm` from a test. Its review (round 2, 2026-10-26) found two writers it does not cover: hooks/merge-guard.sh `record()` and hooks/lead-stop.sh `log()` append to `<project>/.swarm/events.tsv`, where the project comes from the call's cwd, so a test that runs a hook from a story worktree writes the live log. Make both hooks apply the same guard swarm.sh does (SWARM_FORBID_PROJECT, compared by physical path and by the worktree's main checkout).

**Done when:**
- A test runs each hook from a story worktree under the guard and shows the main checkout's .swarm/events.tsv is unchanged; with the guard removed, the same test fails.
- `make test` passes.

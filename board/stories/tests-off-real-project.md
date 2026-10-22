---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [scripts/test.sh, bin/lib/dash.sh:slow refresh spawn, tests/test_runner_test.sh]
easy: true
estimate_lines: 80
---

# make test never reaches the real project: no inherited SWARM_PROJECT, no detached refresh left behind

This was the main GitHub budget drain on 2026-10-22, found by the backlog conductor. Builders run with SWARM_PROJECT set to the real project, and `make test` inherits it. The dash tests (tests/dash_*_test.sh, such as dash_stalls_test) then leave detached CI refreshes behind: dash_slow.py, started from bin/lib/dash.sh (around :155) and reparented to launchd. Those run `swarm.sh flow --since 2026-10-16` against the real repo and its .swarm/ files. GitHub's REST and GraphQL budgets each hit 0 more than once that evening, stalling every agent. Telling builders to run `env -u SWARM_PROJECT make test` didn't hold: the conductor's reaper still caught 20 refreshes afterwards.

scripts/test.sh unsets SWARM_PROJECT (and SWARM_AGENT and the other swarm env names that point at a real project) for every test file, with the rest it unsets at line 36. dash.sh starts no detached refresh when SWARM_SLEEP_SCALE is set (test mode) or when a new SWARM_DASH_NO_REFRESH is set, which test.sh sets. A dash test that needs the refresh runs it in the foreground against its fixture project.

**Done when:**
- A test (tests/test_runner_test.sh, or an existing runner test) runs a stub test file through scripts/test.sh with SWARM_PROJECT set in the caller, and the stub sees it unset.
- Running every tests/dash_*_test.sh leaves no dash_slow.py or swarm.sh process alive afterwards: pgrep finds none started under the test's temp dirs or against the real project.

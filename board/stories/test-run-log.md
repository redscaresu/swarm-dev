---
kind: code
status: ready
depends_on: []
touches: [scripts/test.sh:start and end of a run, bin/lib/flow_test_runs.py (new), bin/lib/flow.sh:test_runs section wiring, tests/flow_test_runs_test.sh (new), docs/reference.md:flow entry]
estimate_lines: 140
easy: false
---

# Every local test run is logged with the load it ran under, and flow reports it

At 14:51 on 2026-10-24 the lead found every builder idle, each waiting on its own `make test`. Eight full suites were running at once (JOBS=3 or 4), plus two mutation runs. The load average was 45 to 50 on 10 CPUs, and suites ran for 40 to 55 minutes. Nothing recorded this. The lead found it with `ps` and `uptime`. The user chose to leave builds as they are for now, but wants this tracked, so that a test queue or a JOBS change can be decided from data.

- At the start and the end of every run, scripts/test.sh appends one line to the main checkout's `.swarm/test-runs.tsv`, found through `git rev-parse --git-common-dir`. The line holds:
  - the start and end times, and seconds taken
  - JOBS, and the TESTS filter (or `all`)
  - the worktree's branch
  - the 1-minute load average and the number of CPUs
  - how many other `scripts/test.sh` runs are going at that moment
  - the exit status
- A write that fails never fails the run. Tests run with the swarm environment unset (#385), so this must not depend on SWARM_PROJECT.
- Add a `test_runs` section to `swarm.sh flow`. It shows full-suite runs by how many ran at once (1, 2, 3 to 4, 5 or more), with the median and p90 seconds and the median load at start, and lists the 5 slowest full runs with their branch and concurrency.

**Done when:**
- A test runs scripts/test.sh on a one-file filter in a temporary repo. It checks that a line is written with every field, and that an unwritable `.swarm` still leaves the run's exit status unchanged.
- tests/flow_test_runs_test.sh, on a fixture test-runs.tsv: the buckets, medians and slowest list match.
- `make test` passes.

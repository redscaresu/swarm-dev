---
kind: code
status: later
depends_on: []
touches: [tests/the slowest files found, scripts/test.sh:shard balance if needed]
estimate_lines: 120
easy: false
---

# The slowest test files get faster

For 0.28. Part of the test-speed evidence in retro-and-shared-rules' appendix. Full local suites took 20 to 55 minutes on 2026-10-24, and CI takes about 3.8 minutes against a 3-minute target (ci-three-minutes). Some of that is the suite itself, not contention.

- Rank the test files by time: CI's per-job timings (`swarm.sh flow`'s ci_health) and a quiet local run at default JOBS, timed per file. Post the top 10 in the PR.
- Fix the worst one or two: fixed sleeps that can poll instead, long timeouts in stubs, repeated setup that can be shared. Coverage stays the same: no test is dropped or weakened.

**Done when:**
- The PR lists the top 10 files with times before and after, and the files it changed are each at least 30% faster on a quiet local run.
- `make test` passes.

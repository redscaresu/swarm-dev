---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [scripts/test.sh, tests/test_runner_test.sh]
estimate_lines: 60
easy: true
---

# make test kills a test file that runs past its time limit and fails it by name

On 2026-10-22 the gh-graphql-budget builder (#347) ran tests/review_test.sh. The test started a `watch --backlog` that never returned, and the builder sat busy for nearly three hours until the conductor killed the watch, the test and its shell by PID. A hung test should fail in minutes, not hold a builder for hours.

scripts/test.sh runs each test file under a time limit, `TEST_FILE_TIMEOUT` seconds (default 300; the slowest file today takes well under that). bash 3.2 and macOS have no `timeout` by default, so it starts the file in its own process group and a watchdog kills the group at the limit. A file killed this way fails with `TIMEOUT <file> after <n>s` in the summary, and its last 20 lines of output are printed. CI's shards get the same limit.

**Done when:**
- A test in tests/ runs scripts/test.sh on a fixture file that sleeps past a 2-second limit: it fails with `TIMEOUT` and the file's name, the run takes under 10 seconds, and no process from the fixture is left running (`pgrep -f` on its marker finds none).
- A fixture file that finishes inside the limit still passes, and `make test` passes.

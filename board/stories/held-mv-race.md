---
kind: code
status: ready
depends_on: []
touches: [tests/binary_fetch_test.sh:held mv cases]
estimate_lines: 60
easy: true
fix: true
---

# Make binary_fetch_test.sh's "held mv" cases deterministic

On 2026-11-22 main's CI at e9278e7 failed tests/binary_fetch_test.sh on its first attempt and passed on the rerun. The failing lines were "held mv: the second writer's mv is held: want 'yes', got 'no'" and the two that follow it. The case at about :17 and :299-305 runs two writers and expects the second writer's mv onto <copy>/swarm to be held while the first runs. On a busy runner the second writer can reach its mv before the hold is in place, so the case races. This was logged as the deferred finding flaky-held-mv-race on #1126.

- Make the hold deterministic. The second writer waits on a file or fifo the test creates once the first writer holds, rather than on timing or a sleep. Keep what the case checks: the second writer's mv is held, its source is in a .fetch-* folder of the copy, and the source is executable and the same as the release.
- Change no code under bin/: this is a test fix.

**Done when:**
- tests/binary_fetch_test.sh passes 20 times in a row on this Mac: `for i in $(seq 20); do make test TESTS=tests/binary_fetch_test.sh JOBS=1 TEST_RUNS_LOG= || break; done`. The PR records the count.
- The held-mv checks still go red when the hold is removed from the test's stub (proved on a copy of the worktree without .git).
- scripts/select-tests.sh --run passes

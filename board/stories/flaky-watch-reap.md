---
kind: code
status: ready
epic: flaky-tests
depends_on: []
touches: [tests/test_helpers.sh:stop_group (new helper), tests/watch_opened_test.sh:watch_for, tests/watch_opened_test.sh:EXIT trap, tests/queue_test.sh:watchrun, tests/queue_test.sh:EXIT trap, docs/lead-by-hand.md:A flaky test, docs/features.tsv:flaky-tests row]
estimate_lines: 120
easy: false
---

# Stop a test's watch as a whole process group before its temp root goes (watch_opened_test, queue_test, #698)

Needs no other story. Cause, from the CI logs (gh run view <id> --repo redscaresu/swarm-dev --attempt 1 --log-failed): a killed watch's descendants still write under ROOT. watch_opened_test 2 of 2 runs read: `rm: cannot remove ...: Directory not empty` after all checks pass (40682631799, 40634154719). queue_test 6 of 6 read: 3 the same rm error (41147355075, 40557075340, 40270810385), 3 the check at tests/queue_test.sh:132 got '(still watching)|1' (40669370466, 40463059549, 40440699358), a pulls/3 call most likely logged by the watch killed at :129 after :132's watchrun emptied gh.log. Both files stop a watch with one pgrep -P snapshot or pkill -P (tests/watch_opened_test.sh:102-103, tests/queue_test.sh:109) and their EXIT traps only rm -rf (:14, :18). Fix: run each watch as its own process group and stop the group (STOP, then KILL, as tests/codex_test.sh:174-187 does for macOS), then poll until pgrep -g finds none, bounded. A pgrep -P walk misses a child re-parented to init. watch_for runs inside $(...) (tests/watch_opened_test.sh:108), so a shell variable never reaches the trap: record the group in a file the EXIT trap reads before rm -rf. Put the helper in tests/test_helpers.sh (two files need it, epic Areas). It must run nothing at source time (tests/live_logs_test.sh checks every file's source line). Keep every check's text. Remove docs/lead-by-hand.md's '## A flaky test' entry (47-53), not 105-111 as the epic says. Add the epic's docs/features.tsv row. feature: CI flakes per 100 PRs. landed: flaky-tests. metric: `flow ci_health: flakes per 100 PRs (flakes / prs x 100), bar under 3`. baseline: 15 over 119 PRs (HLD:93). uses: as row 47. The column after the colon must be one ci_health prints (bin/lib/flow_ci_health.py:409; tests/features_test.sh:155-175). In the PR, list the other test files that start a background process with an EXIT trap that stops nothing: 29 of 181 by a grep at 2a07799c. They are for a follow-up, not fixed here. Run the 20 runs one file at a time, `make test TESTS=<file> JOBS=1`, within the 4-CPU cap. queue_test is SLOW, about 2 min a run.

**Done when:**
- In the PR, each of the 8 runs listed in scope is named with its failing line, quoted from its log.
- watch_opened_test.sh and queue_test.sh start each watch as its own process group. watch_for and watchrun return only once pgrep -g finds no process of that group, and the EXIT trap stops any group still recorded before rm -rf.
- Forced-race proof in a worktree copy without .git: a gh stub leaves a child that writes under ROOT about 1 s after the watch is stopped. With the old stop code, that run fails with 'Directory not empty' or the :132 check. With the fix, it passes. The PR quotes both.
- Proof that the group stop is needed: with only the direct child killed in the copy, the forced-race run goes red.
- 20 runs of make test TESTS=tests/watch_opened_test.sh JOBS=1 and 20 of TESTS=tests/queue_test.sh JOBS=1, one at a time, all green. The counts are in the PR.
- docs/lead-by-hand.md has no '## A flaky test' section.
- docs/features.tsv has the flaky-tests row naming `flow ci_health: flakes`, and tests/features_test.sh passes.
- shellcheck is clean on the touched files, and scripts/select-tests.sh --run is green.
- The PR says the humanizer pass ran over the docs/lead-by-hand.md and docs/features.tsv prose.

---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core]
needs: diff-run-core (tests/diff_run.sh: the shims, the calls:fg stream and the group wait)
touches: [tests/diff_run.sh:step tags and in-order compare, tests/diff_run.sh:times option, tests/diff_run.sh:setsid wait, tests/diff_run_order_test.sh]
estimate_lines: 250
---

# Stub calls are compared in order on the foreground path and within each background step

Uses diff-run-core's shims and its calls:fg stream. A forked subshell keeps its parent's argv, so argv cannot name a step: note_wake_later's `( ... ) &` (bin/lib/agents.sh:2127-2140) would share the foreground's tag. The shims log each call's chain of ancestor pids, and the run notes the processes still alive when the fixture's top command exits. A background step is one of those with everything under it, labelled by its argv and its first call; its calls go to calls:<label>, in order. Every other call stays on calls:fg, in order, whatever the top command is (swarm.sh or a hook). Steps are matched by label, never by position, and a call the run cannot place in one step is red, naming it. A process that leaves the group by setsid, as four detached runs do (bin/lib/lifecycle.sh:2128,3772,4358,5465), is waited for too, found by a marker variable it inherits. merge's `( ... ) &` steps are each waited on at once (bin/lib/merge.sh:1378-1379,1389-1390,1433-1434,1448-1449), so they stay on the foreground path. `--times N` repeats each fixture N times per tree and is red when any run differs from the first.

**Done when:**
- (1) Three synthetic fixtures, one with an anonymous `( ... ) &` subshell, one with a detached swarm.sh run and one with a setsid'd run, whose gh calls land at a random point among the foreground's, compare clean ten runs in ten, and each fails under one global order. (2) Two calls swapped within the foreground, and two within a background step, are each red, naming the step. (3) A stub that alternates its answer by run number is red under `--times 2`; on a worktree copy without .git, removing the compare with the first run turns the test red. (4) Every fixture on main when the PR opens compares clean under `--times 3` on two copies, and every allow list entry on main applies as it did before the PR. (5) tests/diff_run_order_test.sh checks (1)-(3) in under 120 s on its CI shard.
- scripts/select-tests.sh --run passes

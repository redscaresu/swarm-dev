---
kind: code
status: ready
depends_on: []
touches: [bin/lib/build.sh:builder brief test-run stop line, scripts/test.sh:runner wait and TERM trap, tests/test_runner_test.sh:cancellation case]
estimate_lines: 120
easy: false
---

# Stopping a builder's test run stops the whole test tree

A post-merge codex pass on #842 (builder-pushes-once) found this. The builder brief (bin/lib/build.sh, the line telling a builder to stop its test run by the PID it started) assumes that kills the run. But `scripts/select-tests.sh --run` execs make, which starts scripts/test.sh, and the runner waits on a foreground xargs pipeline (scripts/test.sh:438). Killing the launcher's PID leaves that tree running. Even when TERM reaches the runner, bash defers its cleanup trap until the foreground pipeline ends. So tests can keep running after the builder pushes, holding CPU and test slots.

First reproduce it: start a run, kill the launcher's PID, and show test processes still alive. Then make the runner's wait interruptible (run the pipeline in the background and `wait` on it, so the TERM trap runs at once and kills its children), or have the brief stop the process group. Say which in the PR.

**Done when:**
- A test starts scripts/test.sh on a fixture with a slow test file, sends TERM to the launcher, and within 10 s no process from that run is left (checked by its process group or a marker in its command line)
- That case goes red with the change removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- The brief's stop line says what actually stops the run
- scripts/select-tests.sh --run passes

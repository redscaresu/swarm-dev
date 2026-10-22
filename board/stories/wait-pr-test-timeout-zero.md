---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/wait_pr_test.sh, bin/lib/merge.sh:wait_pr]
easy: true
estimate_lines: 30
---

# wait_pr_test's "check reads retried past --timeout" reads 0 times under load

PR #352's CI (run 39763858679, shard 8) failed `check reads retried past --timeout: one read: want '1', got '0'` and its `says so` check, then passed on a rerun. The case runs `--timeout 0` (tests/wait_pr_test.sh:249) and wants exactly one read before the deadline. A slow runner can pass the deadline before the first read. Decide which is right, the contract that wait-pr always reads once even at `--timeout 0`, or the test, and fix that side.

**Done when:**
- `swarm.sh wait-pr --timeout 0` reads the checks once before it gives up, or the test no longer depends on the clock; the PR says which and why.
- tests/wait_pr_test.sh passes 20 runs in a row with the CPU loaded (say how).

---
kind: code
status: blocked
epic: test-speed
depends_on: [slow-test-files]
needs: [slow-test-files: the faster tests/merge_test.sh and tests/wait_pr_test.sh and the Makefile:SLOW comment it changes]
touches: [.github/workflows/ci.yml:test-shard matrix, Makefile:SLOW, Makefile:SERIAL, tests/test_shard_test.sh]
estimate_lines: 60
easy: true
---

# A PR's required checks finish in about three minutes

Needs slow-test-files' faster tests/merge_test.sh and tests/wait_pr_test.sh, and its Makefile:SLOW comment, which change the per-shard times and what SLOW should hold. Adopted: epic test-speed, status ready, touches as file:part. Baseline: main's green runs 40238681988 and 40237857410 (2026-10-25) took a slowest test-shard of 281 s and 396 s. Shard 2 holds merge_test, which ran 276-393 s on its own. Rebalance by SLOW/SERIAL moves (Makefile:18-23) or the shard count in ci.yml's test-shard matrix (.github/workflows/ci.yml:51-52), or cache what the slowest step rebuilds. Change the count only as far as this needs (epic Out of scope). tests/test_shard_test.sh pins the matrix as 1..N with SLOW+SERIAL at most N (8 of 8 today). Do not touch Makefile's test recipe (codex-runs-no-tests) or ci.yml's shellcheck and compile steps (select-tests-by-file). ci.yml is a board-only gate file (scripts/board-only.sh:18), so the PR runs the base's gate. The 10-PR median is read at the v0.29.0 release story (epic Done when 6). The repo is public, so more shards cost no money.

**Done when:**
- The PR shows, from its own head's CI run and from the two baseline runs, the required checks' wall time (first job start to the `test` check's end) and the slowest job. The head's wall time is under 180 s, or the PR names the job over it and why. Either way it is lower than both baselines.
- tests/test_shard_test.sh passes with every SLOW, SERIAL or matrix change the PR makes.

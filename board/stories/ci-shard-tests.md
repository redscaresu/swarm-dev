---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [.github/workflows/ci.yml, scripts/test.sh]
estimate_lines: 60
easy: true
---

# CI shards the test suite so a code PR's checks finish in under 3 minutes

after-release-checks (2026-10-22) measured the last code PRs' CI at 9m22s (#330, run 39682994418), 9m36s (#327) and 10m46s (#334). The `test` job alone was 9m19s; every other job is under 1m10s. The target is under 3 minutes. `make test` already runs the files in parallel (scripts/test.sh, JOBS), but one runner has few cores.

Split the `test` job into a matrix of N shards (start with 4). Each shard runs `make test` on its share of tests/*_test.sh, picked by a stable split in scripts/test.sh (for example, the file's index mod N, given `SHARD=i/N`), so every file runs exactly once. The required check stays a single name: add a final `test` job that needs every shard and fails if any shard failed, so branch protection does not change. The board-only gate skips every shard as it skips the job today.

**Done when:**
- A test in tests/ runs scripts/test.sh's split for N = 1, 3 and 4 over the real tests/ list and asserts every file lands in exactly one shard.
- The PR's own CI shows the shards and a green `test` job, with the time from first run created to last run updated under 3 minutes.
- A board-only PR still skips every shard.

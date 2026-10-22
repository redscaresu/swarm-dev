---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/flow_ci_health.py, tests/flow_test.sh]
estimate_lines: 80
easy: true
---

# flow's ci_health names the gh error and retries instead of dropping most PRs

after-release-checks (2026-10-22): `swarm.sh flow --since 2026-10-17` and `flow --epic safer-faster-swarm` both printed `ci health: gh failed`, and gh could not read 26 of about 31 PRs, so the medians covered 5 or 6 PRs. gh's core rate limit was nearly untouched (4932 of 5000 left), so the cause may be a secondary or concurrent limit (two flow runs were running at once).

Find which gh call fails. Retry a failed call up to 3 times with backoff, and when it still fails, print gh's error once with the number of PRs it dropped, instead of a bare `gh failed`.

**Done when:**
- A test with a stub gh that fails twice then succeeds counts that PR. A stub that always fails with a message prints that message and the dropped count.
- `swarm.sh flow --epic safer-faster-swarm` run alone reads every PR in its window, or names the gh error for each one it drops (paste the line in the PR).

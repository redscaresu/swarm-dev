---
kind: code
status: later
depends_on: []
touches: [.github/workflows/ci.yml, Makefile]
estimate_lines: 60
easy: true
---

# CI's median PR time is under 3 minutes

After #343's four shards, the median CI time per PR is 3.8 minutes (`swarm.sh flow --since 2026-10-22`, ci_health, 2026-10-23), against after-release-checks' 3-minute target. Find the slowest shard and job step from that run's `slowest_job` and rebalance the shards, or cache what the slowest step rebuilds.

**Done when:**
- `flow` ci_health over the 10 PRs after the merge shows a median under 3 minutes, posted with the command.

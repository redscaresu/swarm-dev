---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# status-speed

`swarm.sh status` and `dash` answer in seconds

HLD § v0.31.0 additions. In the v0.30.0 build 66 of 77 `status` runs took over a minute (median 119 s, p90 472 s), and `dash` took 885 s once; `next` had a p90 of 192 s.

**Done when:**
- stage: v0.31.0
- `status` and `next` keep to a time budget and reuse the PR and CI state wait-pr and watch already read; `flow run_times` shows the median under 30 s.
- A read cut by the budget is named, as today.

**Out of scope:**
flow-speedups' ruleset and merge-mode changes (still `later`).

**Constraints:**
- stage: v0.31.0. From the HLD's v0.31.0 additions (decided 2026-10-31); /plan-epic scopes it.

**Areas:** bin/lib/lifecycle.sh (status, next), bin/lib/dash*.py, run-times.tsv readers

**Your part:**
- none

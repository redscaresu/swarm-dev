---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/flow_ci_health.py, bin/lib/dash_slow.py, tests/]
---

# CI time per job, and its trend, in flow and dash

The user asked "I thought you sped up the CI"; the answer took hand-run API calls (swarm-dev
10-11 min, infrafactory 8-9 min on 2026-10-18). flow's CI health section adds, per repo, the
median wall time of a PR's CI run and of its slowest job over the window, beside the same figures
for the window before it. dash shows one line: `ci 11m (slowest: test 9m) ▼2m vs last week`.
Use the run and job times gh already returns; no new gh call per PR beyond one jobs listing per
run, and it stays within flow_ci_health's existing time budget.

**Done when:**
- Fixture runs give the right medians, slowest job and change against the previous window.
- dash's line matches flow's figures (agreement assertion).

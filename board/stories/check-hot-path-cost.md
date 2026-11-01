---
kind: code
status: later
depends_on: []
checks: hot-path-cost
touches: [scripts/lint:hot-path-cost check, tests/lint_test.sh:hot-path-cost cases]
estimate_lines: 120
easy: false
---

# A check catches the `hot-path-cost` findings reviews keep raising

`hot-path-cost` was fixed on several PRs in the 30 days to 2026-10-26 with no check (swarm.sh outcomes; 21 lines in .swarm/findings.tsv). Recent cases:
  - https://github.com/redscaresu/swarm-dev/pull/544: missing_arms reads swarm.md line by line per step: declined, nit
  - https://github.com/redscaresu/swarm-dev/pull/541: restart's herdr and gh reads have no time limit while it holds the step-up lock
  - https://github.com/redscaresu/swarm-dev/pull/541: handover_brief and base_for run gh with no time limit under the lock: outside touches

Find the mechanical form these share, if any, and add a lint, test or review-prompt line that catches it. If no mechanical form exists, add one line to the review brief naming the pattern, and say so in the PR.

**Done when:**
- The check (or brief line) flags a fixture of the pattern and passes a clean one; the flag case goes red with the check removed.
- `make check` passes on main.

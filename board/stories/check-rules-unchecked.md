---
kind: code
status: later
depends_on: []
checks: rules-unchecked
touches: [scripts/lint:rules-unchecked check, tests/lint_test.sh:rules-unchecked cases]
estimate_lines: 120
easy: false
---

# A check catches the `rules-unchecked` findings reviews keep raising

`rules-unchecked` was fixed on several PRs in the 30 days to 2026-10-26 with no check (swarm.sh outcomes; 49 lines in .swarm/findings.tsv). Recent cases:
  - https://github.com/redscaresu/swarm-dev/pull/529: six new checks have no FAIL line in the PR body
  - https://github.com/redscaresu/swarm-dev/pull/541: five restart assertions have no FAIL line
  - https://github.com/redscaresu/swarm-dev/pull/539: nine new marker assertions have no FAIL line

Find the mechanical form these share, if any, and add a lint, test or review-prompt line that catches it. If no mechanical form exists, add one line to the review brief naming the pattern, and say so in the PR.

**Done when:**
- The check (or brief line) flags a fixture of the pattern and passes a clean one; the flag case goes red with the check removed.
- `make check` passes on main.

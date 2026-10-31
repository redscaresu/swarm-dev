---
kind: code
status: later
depends_on: []
checks: fails-open
touches: [scripts/lint:fails-open check, tests/lint_test.sh:fails-open cases]
estimate_lines: 120
easy: false
---

# A check catches the `fails-open` findings reviews keep raising

`fails-open` was fixed on several PRs in the 30 days to 2026-10-26 with no check (swarm.sh outcomes; 33 lines in .swarm/findings.tsv). Recent cases:
  - https://github.com/redscaresu/swarm-dev/pull/540: bin-side swarm.sh runs through a handle set outside the function give no arm edge and no full fallback
  - https://github.com/redscaresu/swarm-dev/pull/540: fallback matches an arm word anywhere in a test's text; declined: the story sets this rule (as in round 1)
  - https://github.com/redscaresu/swarm-dev/pull/530: merge exit when findings file lists findings: review status is set only after a passing review

Find the mechanical form these share, if any, and add a lint, test or review-prompt line that catches it. If no mechanical form exists, add one line to the review brief naming the pattern, and say so in the PR.

**Done when:**
- The check (or brief line) flags a fixture of the pattern and passes a clean one; the flag case goes red with the check removed.
- `make check` passes on main.

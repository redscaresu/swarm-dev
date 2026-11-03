---
kind: code
status: later
depends_on: []
checks: fails-silent
touches: [scripts/lint:fails-silent check, tests/lint_test.sh:fails-silent cases]
estimate_lines: 120
easy: false
---

# A check catches the `fails-silent` findings reviews keep raising

`fails-silent` was fixed on several PRs in the 30 days to 2026-10-26 with no check (swarm.sh outcomes; 13 lines in .swarm/findings.tsv). Recent cases:
  - https://github.com/redscaresu/swarm-dev/pull/535: a failed herdr pane list clears the agent list, so dash draws no no-agent row
  - https://github.com/redscaresu/swarm-dev/pull/539: a failed step-up whose new pane is kept never reaches the lead
  - https://github.com/redscaresu/swarm-dev/pull/539: failed step-up unreported without a wait --lead lead: the story asks the conductor to stop listing it

Find the mechanical form these share, if any, and add a lint, test or review-prompt line that catches it. If no mechanical form exists, add one line to the review brief naming the pattern, and say so in the PR.

**Done when:**
- The check (or brief line) flags a fixture of the pattern and passes a clean one; the flag case goes red with the check removed.
- `make check` passes on main.

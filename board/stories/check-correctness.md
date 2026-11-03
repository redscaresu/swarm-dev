---
kind: code
status: later
depends_on: []
checks: correctness
touches: [scripts/lint:correctness check, tests/lint_test.sh:correctness cases]
estimate_lines: 120
easy: false
---

# A check catches the `correctness` findings reviews keep raising

`correctness` was fixed on several PRs in the 30 days to 2026-10-26 with no check (swarm.sh outcomes; 59 lines in .swarm/findings.tsv). Recent cases:
  - https://github.com/redscaresu/swarm-dev/pull/541: check the worktree's branch and git state before naming restart in the no-agent exit
  - https://github.com/redscaresu/swarm-dev/pull/541: EXIT trap pastes the lock path in single quotes: the repo's idiom (merge.sh:706, board.sh:1718); breaks only on a project path with an apostrophe
  - https://github.com/redscaresu/swarm-dev/pull/541: manual step-up racing a restart, and the header overstating the lock: needs two lead commands at once; the manual-step-up lock gap was declined out of

Find the mechanical form these share, if any, and add a lint, test or review-prompt line that catches it. If no mechanical form exists, add one line to the review brief naming the pattern, and say so in the PR.

**Done when:**
- The check (or brief line) flags a fixture of the pattern and passes a clean one; the flag case goes red with the check removed.
- `make check` passes on main.

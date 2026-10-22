---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:watch check-runs read, tests/review_test.sh]
easy: true
estimate_lines: 40
---

# watch reads a rate-limit error from the check-runs API as an error, not as a count

Escaped bug, reported by the backlog conductor on 2026-10-22 and logged against #233. watch's check-runs read (bin/lib/merge.sh, near `gh api "repos/${repo}/commits/${sha}/check-runs"`) takes gh's rate-limit error JSON as its count. So `[[: {: syntax error` prints on every poll while the budget is spent. Check gh's exit code and the output's shape. On an error, count the read as unknown for that poll and say so once on stderr, the way watch handles a failed list since #347.

**Done when:**
- tests/review_test.sh, with a stub gh that prints a rate-limit JSON body and exits 1: watch prints no syntax error, says the read failed once, and polls on.

---
kind: lead
status: ready
epic: flaky-tests
after: flaky-tests
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: read the flake rate, file the class follow-ups, and settle the epic's changes with the user

The epic's Done when bullet 4 (flaky runs per 100 PRs under 3) needs a reading no builder can show. Once the epic's stories have merged and a build has run on a plugin with them: `gh api rate_limit`, then `swarm.sh flow --since <that build's start>` once, and record ci_health's flakes per 100 PRs with its sample. File one `status: later` story per class follow-up the PRs list: test files whose EXIT trap stops nothing (29), today-dated fixtures (33), and `| grep -q` lines (46 in 25 files). The plan has six stories where the epic said three, and moves queue_test's wait-on-a-condition (bullet 2) into the cleanup fix. **You:** agree both changes, or say what to change; the same board PR edits board/epics/flaky-tests.md to match.

**Done when:**
- The flake reading against the bar, with window and sample, is recorded in the PR that finishes this story or the v0.31.0 checkpoint file.
- Three later stories, one per class follow-up, are on the board.
- The user's answer is recorded and board/epics/flaky-tests.md matches it.

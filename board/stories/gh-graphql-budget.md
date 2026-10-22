---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh, bin/lib/agents.sh, tests/wait_pr_test.sh]
estimate_lines: 150
easy: false
---

# The swarm stays inside GitHub's GraphQL budget and says when it runs out

On 2026-10-22 at 00:35 UTC the account's GraphQL budget hit 0 of 5000 for the hour (`gh api graphql -f query='{rateLimit{remaining resetAt}}'`), while REST had 4932 left. `board-pr open` died with "gh cannot list the PRs", and `flow`'s ci_health dropped 26 of about 31 PRs on `gh failed` (flow-ci-health-gh-errors). With one conductor, five builders and the lead's waits running, the swarm's polling (`gh pr list`, `gh pr view`, `gh pr checks`) is mostly GraphQL, and the budget runs dry within the hour.

First measure: count gh calls by command over one hour (wrap gh in the events log, or read `GH_DEBUG` once) and name the top three callers. Then move the hottest polls to REST (`gh api repos/.../pulls`, `.../commits/<sha>/check-runs`), which has its own budget, or cache a PR list for 60 seconds across waits. When gh says the rate limit is exceeded, print the reset time and wait until then once, instead of failing as a gh error.

**Done when:**
- The PR names the top three GraphQL callers with their counts from one measured hour.
- Those three no longer use GraphQL, or share a cache, and a test with a stub gh asserts the REST form is called.
- A stub gh that answers "API rate limit already exceeded" makes wait-pr print the reset time and retry after it, not exit as a gh error.

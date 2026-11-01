---
kind: lead
status: ready
epic: reliable-runs
after: reliable-runs
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: read the gh calls drop, and settle two narrowed goals with the user

The epic's Done when wants `flow gh_calls` to show a drop against the v0.30.0 build's 40,380 REST calls. No builder can show it. Once the epic's code stories have merged and a build has run on a plugin with them, run `gh api rate_limit`, then `swarm.sh flow --since <that build's start>` once, and record gh_calls by caller beside the baseline (this project's gh-calls.tsv, 2026-10-30T11:50Z to 2026-11-01T00:45Z: 40,197 REST rows of 50,419; wait-pr 18,217, watch 10,219, merge 7,740). Two parts of the agreed epic were narrowed by the plan, so they need the user. **You:** accept or reject: a codex usage limit is not retried (it resets in hours; the HLD, :502, asked for a retry). **You:** accept or reject: the 29 codex timeouts in the v0.30.0 build get no story in v0.31.0. A rejection files a story by board PR.

**Done when:**
- The gh_calls reading, by caller, against 40,380 is recorded in the PR that finishes this story or the v0.31.0 checkpoint file.
- Both answers are recorded, and any rejection has its story on the board.

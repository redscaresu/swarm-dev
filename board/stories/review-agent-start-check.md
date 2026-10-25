---
kind: lead
status: ready
epic: no-agent-alert
depends_on: []
touches: []
estimate_lines: 0
easy: false
---

# The first v0.28.0 build shows whether a review agent starts under 0.27.2

This is the epic's Your part (board/epics/no-agent-alert.md:37; HLD Rollout § This machine, board/hld/2026-10-25-swarm-dev-0-28.md:585-588). Watch the first v0.28.0 story build of any epic that reaches review. Read its review-agent lines in events.tsv and its .swarm/reviews/<slug>.head. If no review agent started, file it as this epic's first real case with `swarm.sh intervene lead-hand "<slug> #<pr>: no review agent started under 0.27.2"`. If no-agent-review-gone has not been built yet, copy those events.tsv lines into this file for its fixture. This step is the lead's. The epic names no human step, so there is no **You:** step.

**Done when:**
- This file records the first v0.28.0 build's review-agent lines (slug, PR, outcome) and either 'a review agent started' or the intervene line filed. The lead then deletes the file in a board PR.

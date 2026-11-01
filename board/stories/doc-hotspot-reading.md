---
kind: lead
status: ready
epic: doc-hotspot
after: doc-hotspot
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: read the doc hotspot bar from flow once the column lands

The doc hotspot row's baseline came from a merge-tree replay, not from flow. Once merge-ins-reference-docs has merged and a build has run on a plugin with it, run `gh api rate_limit`, then `swarm.sh flow --since <that build's start>` once, and record merge_ins' reference_docs count against the row's bar. If it is far from the replay's 47 of 62, say so and set the row's baseline from flow in a board PR. No **You:** step.

**Done when:**
- The flow reading of reference_docs, its window and sample, is recorded in the PR that finishes this story or the v0.31.0 checkpoint file, against the bar.

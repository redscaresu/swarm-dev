---
kind: lead
status: ready
epic: review-follows-head
after: review-follows-head
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: check one real review agent follows a mid-review push

The stories test the brief's commands, not a real review agent. Once the epic's code stories have merged and the lead runs a plugin with them, watch the build for one PR whose builder pushed during its review. Record from events.tsv and the review pane: the review agent ran --next on the new head, reviewed it, and gave a verdict on it in the same session, with no `head moved:` restart. If a reviewer instead waited on a builder that had already pushed, record it: that is the cause wait-past-head did not cover (the reviewer missing its own wait's exit), and file a story for it. If no push during a review happens in the v0.31.0 build, say so with the count of review sessions read. No **You:** step: the lead does this alone.

**Done when:**
- The PR that finishes this story (or the v0.31.0 checkpoint file) records one observed mid-review follow with its PR and events.tsv lines, or the cause found and the story filed for it, or 'no push during a review in the build' with the number of review sessions read.

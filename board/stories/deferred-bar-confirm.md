---
kind: lead
status: ready
epic: review-rounds-end
depends_on: []
touches: [board/stories/goal1-flow-readings.md:scope (the bar)]
estimate_lines: 0
easy: false
---

# Confirm the deferred_proved_real bar

Needs nothing from another story. **You:** confirm the bar for deferred findings that later proved real: under 10% of deferred findings (proposed by the epic), or name another. The checkpoint's turn-back trigger reads it (HLD Rollout § Readings). The lead writes your answer into goal1-flow-readings' scope before it starts, then removes this story.

Tell the user, before they confirm the bar: the cap is a constant (CAP_ROUND), not a setting, so if deferred_proved_real goes over the bar, turning it back takes a patch release, not a config line (HLD's turn-back rule).

**Done when:**
- goal1-flow-readings' story file names the bar the user confirmed, and this story file is gone from board/stories.

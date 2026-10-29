---
kind: docs
status: ready
epic: delivery-liveness
depends_on: []
touches: [docs/features.tsv:delivery-liveness rows]
estimate_lines: 6
easy: true
---

# features.tsv rows for Goals 2, 3 and 4

Add three rows to docs/features.tsv, each with landed `delivery-liveness` and an event: uses entry. Goal 2: metric `flow tell_refusals`, baseline 229 of 410 agent-pane tells refused (v0.29.0). Goal 3: metric `flow incidents: stalled inputs`, baseline 7 or more of 20 stalled step-ups false (v0.29.0). Goal 4: metric `flow start_failures`, baseline 48 review agents not restarted within 10 minutes (v0.29.0). The flow sections come from telemetry-writers, which runs later and checks these spellings. Today's check asks only for a metric, a uses entry and a baseline. Rebase first: rules-file-briefs (#717), rung-cost-block (#718) and lead-woken add rows to this file too.

**Done when:**
- docs/features.tsv has the three rows, with metrics spelled `flow tell_refusals`, `flow incidents: stalled inputs` and `flow start_failures`, and those baselines.
- tests/features_test.sh passes; removing one row's baseline turns it red (copy-aside proof).

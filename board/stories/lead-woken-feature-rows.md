---
kind: docs
status: ready
epic: lead-woken
depends_on: []
touches: [docs/features.tsv:lead-woken rows]
estimate_lines: 4
easy: true
---

# features.tsv rows for HLD Goal 5

Add two docs/features.tsv rows, each landed `lead-woken` with uses `event:lead-woken`. Row 1: metric `flow incidents: lead-hand count per 100 merged story PRs (over flow throughput: merged PRs)`, baseline '61 per 100 (48 lead-hand incidents over 79 merged story PRs, HLD 2026-10-28 Goal 5); bar under 15'. Row 2: metric `flow lead_queue: p90_min`, baseline 'unavailable: p90_min lands with telemetry-writers; bar 30 min'. bin/lib/flow_incidents.py, flow_throughput.py and flow_lead_queue.py exist. Rebase first: liveness-feature-rows and other stories add rows to this file too.

**Done when:**
- docs/features.tsv has both rows with those metrics and baselines, and tests/features_test.sh passes.
- Removing one row's baseline turns tests/features_test.sh red (copy-aside proof).

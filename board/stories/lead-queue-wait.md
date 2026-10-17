---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fold-reports]
touches: [bin/lib/flow_lead_queue.py (new), docs/features.tsv:lead-queue-wait row, tests/lead_queue_wait_test.sh (new)]
easy: false
estimate_lines: 140
---

# flow reports how long items wait in the lead's queue, median and max per day

Needs fold-reports' section loader: a new bin/lib/flow_lead_queue.py, using the queue lead_queue defines (bin/swarm.sh:6554). From events.tsv, each held, escalated or awaiting-merge item's minutes from entering the lead's queue to leaving it. flow prints the median and maximum per day; an item still waiting counts up to now and is marked open. features.tsv row.

**Done when:**
- tests/lead_queue_wait_test.sh: a fixture events.tsv with a held, an escalated and an awaiting-merge item over two days gives the right median and maximum per day, and a still-waiting item is marked open.

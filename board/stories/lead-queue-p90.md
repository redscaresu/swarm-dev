---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/lib/flow_lead_queue.py:window totals (new), tests/lead_queue_wait_test.sh:flow p90 case, docs/reference-logs.md:lead_queue paragraph (Flow and features), bin/lib/reports.sh:lead_queue doc comment]
estimate_lines: 70
easy: true
---

# flow lead_queue prints p90_min over the window

bin/lib/flow_lead_queue.py prints `day items median_min max_min open` (flow_lead_queue.py:178), which dash.sh:299-331 and tests/dash_check_test.sh:52 read by position. Keep that table and add, after it and a blank line, `items median_min p90_min max_min` over every item in the window, p90 by nearest rank as flow_test_runs' median_p90 does, `-` with no item. Goal 5's queue bar reads p90_min. Update bin/lib/reports.sh:352's lead_queue comment and docs/reference-logs.md's lead_queue paragraph.

**Done when:**
- tests/lead_queue_wait_test.sh flow case: ten items waiting 1 to 10 minutes print p90_min 9; one item prints its own minutes; no item prints `-` in each column.
- The per-day table is unchanged over the same fixture and tests/dash_check_test.sh passes.
- Copy-aside proof: printing the median as p90_min turns the ten-item case red.
- docs/reference-logs.md names p90_min; tests/doc_check_test.sh passes.

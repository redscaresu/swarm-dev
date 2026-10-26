---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule, no-agent-step-up-marker, no-agent-dash-rows, flow-kept-items]
needs: [no-agent-rule: the `no-agent` events.tsv line and lead_wake's lead-woken kinds (bin/lib/lifecycle.sh), no-agent-step-up-marker: the step-up:failed events line, the ENTER of a step-up failed item, no-agent-dash-rows: the lead's-queue row in bin/lib/dash_render.py that dash_check matches, flow-kept-items: its kept kind in bin/lib/flow_lead_queue.py's ENTER and its dash_check match in bin/lib/dash.sh, which this story extends]
touches: [bin/lib/flow_lead_queue.py:ENTER no-agent kinds, bin/lib/flow_lead_queue.py:no-agent minutes and working count, bin/lib/dash.sh:dash_check lead's queue, docs/features.tsv:no-agent row, docs/reference.md:flow lead_queue, tests/lead_queue_wait_test.sh:no-agent cases, tests/dash_check_test.sh:no-agent item]
estimate_lines: 220
easy: false
---

# flow measures the minutes from a no-agent event to the lead's wake

Uses four earlier stories: no-agent-rule's `no-agent` events line and lead-woken kinds; no-agent-step-up-marker's `step-up:failed` line; no-agent-dash-rows' row; and flow-kept-items' changes to flow_lead_queue.py and dash_check.

flow's lead_queue (bin/lib/flow_lead_queue.py:12-15, 95-122) measures each no-agent item (kinds no-agent, step-up failed and no-review). An item enters on the earliest real event since its agent's last start: its close line, a failed start, `step-up:failed`, or the `no-agent` line. It leaves on its `lead-woken` line. flow gives the median minutes per day. It also counts alerts fired while the builder was working: a no-agent lead-woken whose slug had a builder started and not yet closed at that time. That count must be 0 on the fixture. flow reads only events.tsv, never a marker's mtime.

dash_check (dash.sh:255-276) matches an open item (entered, not yet woken) to dash's row. docs/features.tsv gets the no-agent row: metric `flow lead_queue: no-agent minutes, median`, bar 2 polls (60 s), 0.27 baseline 3.5 h step-up gap and 3h42m unsent brief (HLD Appendix A). no-review items come from fixture lines, so no-agent-review-gone need not be merged first.

**Done when:**
- tests/lead_queue_wait_test.sh: a builder close at T and a no-agent lead-woken at T+90 s give that item 1.5 minutes, rounded as the section rounds. A step-up item is measured from its step-up:failed line, and a no-review item from its failed start.
- The alerts-while-working count is 0 on the fixture, and 1 after the test adds a lead-woken for a slug whose builder was running.
- tests/dash_check_test.sh: dash --check exits 0 with one open no-agent item, and exits 1 naming the lead's queue when its row is removed.
- tests/features_test.sh passes with the new row. reference.md's flow lead_queue section names the kinds and the count. The humanizer ran over that prose, and the PR says so.

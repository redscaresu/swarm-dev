---
kind: code
status: blocked
epic: no-agent-alert
depends_on: [no-agent-rule, flow-kept-items]
needs: [no-agent-rule: no_agent_lines in bin/lib/lifecycle.sh, whose lines dash draws, flow-kept-items: the kept row in bin/lib/dash_render.py's lead queue rows, which this row follows]
touches: [bin/lib/dash.sh:dash_render no-agent lines, bin/lib/dash_render.py:lead queue rows no-agent row, docs/dash.md:lead's queue, tests/dash_needs_you_test.sh:no-agent row]
estimate_lines: 110
easy: false
---

# dash shows each no-agent item in the lead's queue

Uses no-agent-rule's no_agent_lines (bin/lib/lifecycle.sh) and flow-kept-items' kept row in bin/lib/dash_render.py's lead queue rows. dash_render (bin/lib/dash.sh:533-600) passes no_agent_lines' lines to dash_render.py, reading herdr's list once a frame. dash_render.py draws each line as a row in the lead's queue (lq; needs you when lead is off), naming the slug and its exit, after the kept row. Lines that later stories add (step-up failed, no-review) come through as they are. docs/dash.md names the row. no-agent-flow-minutes makes dash_check match flow's no-agent items to this row.

**Done when:**
- tests/dash_needs_you_test.sh: a started story whose builder pane is gone is a row with its exit, in the lead's queue with lead = session and in needs you with lead = off. With the builder listed, there is no row.
- tests/dash_check_test.sh passes unchanged (dash --check exits 0 on its fixture).
- docs/dash.md describes the row. The humanizer ran over that prose, and the PR says so.

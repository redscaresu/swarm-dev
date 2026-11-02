---
kind: code
status: blocked
epic: machine-usable
depends_on: [pane-close-event]
needs: [pane-close-event (the pane-closed event with slug= role= pane=; written by close_pane and tidy --yes.)]
touches: [bin/lib/flow_panes.py (new), tests/flow_panes_test.sh (new), tests/flow_sections_test.sh:section list, docs/reference-logs.md:Flow and features (section list, panes paragraph), docs/reference-logs.md:Commands (flow row section list, 909), bin/lib/reports.sh:flow comment (sections)]
estimate_lines: 170
easy: false
---

# flow panes: minutes from a review pane's merge or handover to its close

Reads pane-close-event's pane-closed lines. New bin/lib/flow_panes.py (standalone, as flow_report.py:1-26 runs every flow_<name>.py; no shared helper exists). Per review agent: minutes from its story's merge event (target the PR URL; the slug comes from the `review` command's event, target <slug>, outcome `ok (<PR URL>)`) or that handover event itself, to the first pane-closed line with slug=<slug> role=review (or an older `close review-<slug>` line); a pane with no close yet reads `open` with its minutes so far. Then a count of those over 30 minutes, in a column named over_30. Reuse events_outcome.py's outcome and fields helpers (bin/lib/events_outcome.py:6), which other flow readers use.

**Done when:**
- New tests/flow_panes_test.sh with fixture events: a pane closed 10 min after its merge, one 45 min after its handover, one never closed (60 min) give over_30 2, and the open one prints `open`; it goes red with the handover pairing removed.
- With no merge or handover in the window, the section prints its header and over_30 0; an open pane past 30 minutes with no close line still counts.
- A retired pane whose close names review-<cut>-done pairs by slug=, not by name (rules.md rule 10).
- tests/flow_sections_test.sh's section lists include `## panes`.
- docs/reference-logs.md § Flow and features lists the panes section and its columns.

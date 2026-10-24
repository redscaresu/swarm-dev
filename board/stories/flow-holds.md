---
kind: code
status: blocked
depends_on: [hold-event]
needs: "hold-event: the events.tsv `hold` line (slug, reason)"
touches: [bin/lib/flow_holds.py, bin/lib/flow.sh, tests/flow_holds_test.sh, docs/reference.md]
estimate_lines: 110
easy: false
---

# flow reports how long ready stories were held, and why

Needs, from hold-event: the `hold` lines in events.tsv.

- Add a `holds` section to `swarm.sh flow`: one row per hold (story, epic, reason, minutes from the first `hold` line to the story's next build start, or `open` while it has not started), and a total of held minutes by reason class (`clash` when the reason names a story or PR, else `other`).
- Read only events.tsv: no gh calls. Check how flow's other sections are wired (bin/lib/flow_*.py, and where flow calls them) and follow that; fix `touches` in the PR if the wiring lives elsewhere.
- One line in docs/reference.md's `flow` entry.

**Done when:**
- tests/flow_holds_test.sh, on a fixture events.tsv: a story held at 10:00 and built at 10:50 reports 50 minutes with its reason; a story held and never built reports `open`; two holds of one story with different reasons count once, from the first.
- `make test` passes.

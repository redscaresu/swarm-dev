---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/touches_rows.py, bin/lib/dash_finished.py, bin/lib/dash.sh:dash_fields, tests/board_state_readers_test.sh (new)]
easy: false
estimate_lines: 120
---

# dash and the touches check read story state from .swarm/state

Builds on the split: bin/lib/touches_rows.py, bin/lib/dash_finished.py and dash_fields in bin/lib/dash.sh. Their own front-matter parsers (bin/swarm.sh:2682-2738, 5023-5073, 5189-5201) read status, prs, held_by, held_for, escalated_from, attempts and kind from .swarm/state/board/stories/<slug> or epics/<slug> (`key: value` lines, the layout board-state-out-of-git writes) first and the file second. Works with or without that story merged.

**Done when:**
- tests/board_state_readers_test.sh: a story whose file says ready and whose state file says review shows in review in dash, and `story --strict` on another story touching the same file refuses and names it; with no state file, both behave as today.

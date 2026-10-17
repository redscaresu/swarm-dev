---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/board.sh:epic_has_stories, open_item, bin/lib/board.sh:next_step, bin/lib/merge.sh:status_report, bin/lib/dash_finished.py, bin/lib/dash_render.py, tests/fixtures/dash/golden-*.txt (regenerate if present), templates/docs/stories/README.md:after row, docs/reference.md:§ epic done, tests/after_key_test.sh (new)]
easy: false
estimate_lines: 180
---

# A lead story marked after: <epic> does not hold its epic open

Builds on the split: epic_has_stories, next_step and open_item in bin/lib/board.sh, status_report in bin/lib/merge.sh, bin/lib/dash_finished.py and dash_render.py's epic bars. One bash predicate (a kind: lead story with an after: line does not count in its epic) used by epic_has_stories (bin/swarm.sh:3074), next_step (:3103), open_item (:3343) and status_report (:4721), and the same rule in dash's python. The story stays on the board and is listed with the lead's stories. templates/docs/stories/README.md documents after:. Regenerate golden frames if they are on your base.

**Done when:**
- tests/after_key_test.sh: an epic whose only open story is an after: lead story counts as done in `next`, `dash` and `status`; with the after: line removed it is open in all three.
- The same test: the after: story still shows in `next` and `status` as a lead story.

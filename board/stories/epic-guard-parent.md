---
kind: code
status: blocked
epic: fixes-027
depends_on: [epic-guard-gaps]
needs: [epic-guard-gaps: bin/lib/board.sh:epic_ticket_parent, less-noise's contents-reader story (no slug yet): the reader behind merge_read]
touches: [bin/lib/board.sh:epic_ticket_parent, docs/reference.md:parent: sentence of board-pr open's epic check, tests/board_pr_test.sh:parent ticket cases, tests/merge_rules_test.sh:parent ticket cases]
estimate_lines: 60
easy: true
risk: high
---

# The epic guard reads parent: at the head too

Uses epic-guard-gaps' epic_ticket_parent. Merge after less-noise's contents-reader story. Today parent: counts when it names an epic that is active or split at the base (bin/lib/board.sh:933-937). Make it count only when that epic is active or split at the head too, so one PR cannot demote the parent and add an active child.

**Done when:**
- tests/board_pr_test.sh and tests/merge_rules_test.sh: a PR that sets the parent to draft and adds an active child naming it is refused by board-pr open and by merge --board. Both fail on the base.
- A PR that adds an active child of a parent that is active at both ends passes both.

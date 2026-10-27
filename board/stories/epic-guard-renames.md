---
kind: code
status: blocked
epic: fixes-027
depends_on: [epic-guard-gaps, epic-guard-story-merge, plan-drafted-closed-pr]
needs: [epic-guard-gaps: bin/lib/board.sh:epic_unticketed as it restructures it, epic-guard-story-merge: bin/lib/merge.sh:epic_guard, called on the story path too, plan-drafted-closed-pr: shares bin/lib/lifecycle.sh:board_pr (it edits the done arm, this story the open arm's epic check), less-noise's contents-reader story (no slug yet): the reader behind merge_read]
touches: [bin/lib/board.sh:epic_unticketed, bin/lib/merge.sh:epic_guard, bin/lib/merge.sh:merge_gone, bin/lib/lifecycle.sh:board_pr open epic check, docs/reference.md:rename sentence of board-pr open's epic check, tests/board_pr_test.sh:rename cases, tests/merge_rules_test.sh:rename cases]
estimate_lines: 150
easy: false
risk: high
---

# The epic guard follows a renamed epic to its old path

Uses epic-guard-gaps' epic_unticketed and epic-guard-story-merge's epic_guard, which this story edits too, on both its paths. It also shares bin/lib/lifecycle.sh:board_pr with plan-drafted-closed-pr. Merge after less-noise's contents-reader story. epic_guard and board-pr open hand epic_unticketed a flat file list (bin/lib/merge.sh:176-185; lifecycle.sh:97), so a renamed epic looks added. Renaming an active epic is refused as unticketed, and a rename launders a stale agreed: because it reads as new. Pass rename pairs into epic_unticketed: GitHub's previous_filename on the merge path (as merge_gone reads it, merge.sh:158-161) and `git diff -M --name-status` on board-pr open. Read a renamed epic's base copy at its old path.

**Done when:**
- Renaming an active epic with no other change passes board-pr open and merge --board. Fails on the base.
- Renaming a draft whose agreed: its base copy already had, and setting it active, is refused by board-pr open and by merge --board. Both fail on the base.

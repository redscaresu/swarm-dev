---
kind: code
status: blocked
epic: fixes-027
depends_on: [epic-guard-gaps]
needs: [epic-guard-gaps: bin/lib/board.sh:epic_ticket_agreed, less-noise's contents-reader story (no slug yet): the reader behind merge_read]
touches: [bin/lib/board.sh:epic_ticket_agreed, bin/lib/board.sh:AGREED_MAX_AGE, docs/reference.md:agreed: sentence of board-pr open's epic check, tests/board_pr_test.sh:agreed date cases, tests/merge_rules_test.sh:agreed date cases]
estimate_lines: 70
easy: true
risk: high
---

# The epic guard refuses an old or future agreed: date

Uses epic-guard-gaps' epic_ticket_agreed. Merge after less-noise's contents-reader story. Today any agreed: date the base lacks counts (bin/lib/board.sh:932). Make it count only when it is a real date, not after today and no more than AGREED_MAX_AGE days before it. AGREED_MAX_AGE is a named constant; 7 is suggested. The check uses today, not the PR's merge base, which moves when the branch is updated from main. The lead's later-epic path (agreed: <today>, from epic-guard-gaps) still passes.

**Done when:**
- board-pr open and merge --board each refuse a PR adding an agreed: date older than AGREED_MAX_AGE days, and one dated tomorrow. All fail on the base.
- Today's date, and one a day inside the limit, pass both.

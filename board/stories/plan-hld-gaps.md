---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/board.sh:hld_blocked, bin/lib/board.sh:next_step plan-hld arm, bin/lib/board.sh:waiting_on_user HLD arm, docs/reference.md:blocked-HLD sentence beside next's plan-hld rule, tests/next_test.sh:HLD name cases]
estimate_lines: 90
easy: true
---

# next does not offer /plan-hld for an HLD whose name board-pr refuses

An HLD named outside [a-z0-9-] passes next (item_hld's pattern, bin/lib/board.sh:981). But board-pr (bin/lib/lifecycle.sh:57), grants (board.sh:1197) and finish_item (:1449) refuse it, so /plan-hld runs to the end and then fails. Add hld_blocked <hld file>, which prints why an HLD cannot be planned, or nothing. This story checks the name; hld-epics-last adds a second check. next's plan-hld arm (:293-298) skips an HLD that hld_blocked names. waiting_on_user's HLD arm (:1276-1283) lists it as `hld cannot be planned: <slug>, <why>`, naming the fix: rename the file and every hld: that names it. Add a sentence for this beside docs/reference.md:401-402, leaving that sentence to hld-outside-resume.

**Done when:**
- tests/next_test.sh: agreed HLDs named a_b and a.b get no plan-hld step, and the gate lists each with the rename. Fails on the base.
- An agreed HLD with a valid name still gets `plan-hld <hld>`.

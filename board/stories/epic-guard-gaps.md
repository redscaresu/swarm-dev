---
kind: code
status: blocked
epic: fixes-027
depends_on: [plan-hld-gaps]
needs: [plan-hld-gaps: shares bin/lib/board.sh:waiting_on_user (it adds the HLD arm's line; this story edits the later-epic hint), less-noise's contents-reader story (no slug yet): the PR-contents reader behind merge_read, which merge --board's epic check reads through]
touches: [bin/lib/board.sh:epic_unticketed, bin/lib/board.sh:epic_ticket_agreed, bin/lib/board.sh:epic_ticket_parent, bin/lib/board.sh:waiting_on_user later-epic hint, commands/swarm.md:gate handler later epic line, docs/reference.md:status sentence of board-pr open's epic check, tests/board_pr_test.sh:parked ticket cases, tests/merge_rules_test.sh:staged flip and later path cases, tests/next_test.sh:later epic hint, tests/lead_handler_test.sh:gate handler cases]
estimate_lines: 170
easy: false
risk: high
---

# The epic guard needs a ticket for a later, split, review or done epic going active

Shares bin/lib/board.sh:waiting_on_user with plan-hld-gaps. Merge after less-noise's contents-reader story (fixes-027.md:27); the lead adds it to depends_on once it has a slug. (1) Move epic_unticketed's agreed: and parent: checks (board.sh:931-938) into epic_ticket_agreed and epic_ticket_parent, beside hld_ticket, accepting exactly what they accept today. Then epic-guard-dates and epic-guard-parent each change one function. (2) Only `active` at the base passes with no ticket (:930). An epic that is later, split, review or done at the base needs a ticket at the head, as a draft does. (3) The lead can still start a later epic that has no agreed:, parent: or hld: (four on this board, e.g. board/epics/flow-speedups.md): on the user's go, it sets the epic active and writes agreed: <today> in the same edit, as /epic does. Say so in the gate's hint (board.sh:1260) and handler (commands/swarm.md:485). (4) Keep the refusal text, which board_pr_test.sh:342 and merge_rules_test.sh:487 pin. (5) Add the epic's staged-flip test (fixes-027.md:14). Update the status sentence of docs/reference.md § The lead (:34-38).

**Done when:**
- tests/board_pr_test.sh: for each of later, split, review and done at the base, a PR that sets the epic active with no ticket is refused. Each case fails on the base.
- A later epic with no agreed:, parent: or hld:, set active with agreed: <today>, opens through board-pr and merges through merge --board.
- tests/merge_rules_test.sh: a draft epic with stage: and hld:, under an HLD that grants epics, is set active by a board PR that merge --board merges. The test goes red if the flip is refused.
- The existing epic-ticket cases pass unchanged after the move to helpers.
- tests/next_test.sh pins the new later-epic hint, and tests/lead_handler_test.sh pins the handler line.

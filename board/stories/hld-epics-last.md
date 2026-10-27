---
kind: code
status: blocked
epic: fixes-027
depends_on: [plan-hld-gaps]
needs: [plan-hld-gaps: bin/lib/board.sh:hld_blocked and the gate line it prints]
touches: [bin/lib/board.sh:hld_blocked, docs/reference.md:blocked-HLD sentence beside next's plan-hld rule, tests/next_test.sh:HLD Epics cases]
estimate_lines: 50
easy: true
---

# next says why when an HLD's last section is not ## Epics

Uses plan-hld-gaps' hld_blocked and its gate line. An agreed HLD with no `## Epics`, or with a section after its last one (epics_last fails, bin/lib/board.sh:1051), makes the plan PR fall to none, because plan_head (:1062) has nowhere to put the links. Add that check to hld_blocked ('end the HLD with ## Epics'), so next skips the HLD and the gate says why. Extend plan-hld-gaps' docs sentence.

**Done when:**
- tests/next_test.sh: an agreed HLD with no ## Epics, and one with an appendix after ## Epics, get no plan-hld step, and the gate line names ## Epics. Both fail on the base.
- An HLD that ends with ## Epics still gets `plan-hld <hld>`.

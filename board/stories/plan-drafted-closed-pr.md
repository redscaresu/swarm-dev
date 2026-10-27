---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [hooks/lead-stop.sh:plan_drafted, bin/lib/lifecycle.sh:board_pr done arm, tests/lead_stop_test.sh:plan_drafted cases]
estimate_lines: 60
easy: true
---

# lead-stop does not count a closed plan PR's critic.json as a drafted plan

plan_drafted (hooks/lead-stop.sh:149-171) counts .swarm/<subject>/critic.json as a drafted plan when it parses and is newer than the epic or HLD file. A closed plan PR leaves that file behind, so the lead's turn can end with nothing to wait on. Have `swarm.sh board-pr done` for a plan-<hld> or scope-<epic> PR that closed unmerged clear the subject's critic.json, or have plan_drafted ignore it; fix both callers (:176-177). A plan that is reported and waits on the user's approval, with no board PR yet, must still count. The epic's Constraints say hooks/ edits are not held for the user this stage.

**Done when:**
- tests/lead_stop_test.sh: after a plan PR closes and board-pr done runs, a critic.json left from that plan is not counted as drafted, for plan-hld and plan-epic. Fails on the base.
- The existing critic.json cases (tests/lead_stop_test.sh:148-180) pass, including a reported plan with no board PR yet.

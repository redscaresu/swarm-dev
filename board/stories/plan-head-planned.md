---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/board.sh:plan_head, tests/grants_test.sh:plan_head cases]
estimate_lines: 70
easy: true
risk: high
---

# plan_head accepts a plan PR's planned: only where next reads the HLD as unplanned

plan_head (bin/lib/board.sh:1062-1069) decides whether a board PR only plans its HLD, and so whether the HLD's merge grant covers it. Test the cases in Done when against the current code, and fix those that give the wrong answer. A board copy that is already planned is a reversal of today's rule (:1066): a planned HLD is never due a plan (hld_due, :1012), so a second plan PR rides no grant. board.sh:1065 (`[[ "${h}" =~ ${re} ]]`) is a loose-match site; loose-match-regex marks it after this story merges.

**Done when:**
- tests/grants_test.sh accepts: a board copy with no planned: and a head with `planned: <today>` and epic links; a board copy with `planned: ""` and the same head, where `swarm.sh grants <plan PR URL>` names the HLD.
- It rejects: a board copy already planned (planned: D) with a head keeping planned: D; a head with `planned: ""`; a head with two planned: lines; a head whose planned: is not YYYY-MM-DD.
- Each case that gives the wrong answer on the base passes after the fix. The PR names which cases those were.

---
kind: docs
status: ready
epic: fixes-027
depends_on: []
touches: [commands/plan-epic.md:ground rules, commands/plan-epic.md:step 2 story rules, commands/plan-epic.md:step 3 verify skeptic, commands/plan-hld.md:brief opening, tests/plan_epic_test.sh:retro rule cases, tests/plan_hld_test.sh:brief cases]
estimate_lines: 40
easy: true
---

# Planning briefs split big detection stories, add depends_on only for a real need, and write output early

Three rules, from the v0.28.0 retro and the user (2026-10-26). (1) commands/plan-epic.md step 2 (:65): split a story that adds detection logic (a new alert, check or classifier) and runs over about 200 lines before the board PR. The general cap stays one changed behaviour and about 300 lines, so the pins at tests/plan_epic_test.sh:87-88 stay. The skeptic's refute list (:85) checks it too. (2) Step 2 (:73): give a story depends_on only when it uses something the other adds (named in needs) or shares a touches part, never for ordering alone; maximise concurrency by default. (3) The ground rules in the briefs of commands/plan-epic.md (:31-33) and commands/plan-hld.md (:82-86) tell the agent to write its output file early and update it as it goes, so a timed-out turn loses one item, not all. Run the humanizer over the changed prose.

**Done when:**
- tests/plan_epic_test.sh pins the detection split rule in step 2 and in the skeptic's refute list, and the depends_on rule in step 2. Each fails on the base. The 300-line pins at :87-88 pass unchanged.
- tests/plan_epic_test.sh and tests/plan_hld_test.sh pin the write-early line in both briefs' ground rules. Both fail on the base.

---
kind: code
status: ready
epic: reference-split
depends_on: []
touches: [tests/merge_test.sh:reference.md § Merging check, tests/epic_codex_test.sh:notreviewed and bare_declined reads, tests/epic_briefs_test.sh:docs clash-rule check, tests/skill_test.sh:copied-line check, tests/plan_epic_test.sh:M default and method-section read, tests/upgrade_test.sh:docs describe it, tests/command_names_test.sh:bare /swarm grep, scripts/test-map.tsv:docs row floor]
estimate_lines: 40
easy: true
---

# Tests read docs/reference.md's sections by heading across every docs/reference*.md

Seven tests name docs/reference.md by path. After the split the sections they read move to other files, and three of them check one file for a rule that spans every file (rules.md:10-11). On today's tree, retarget each one to read the set docs/reference*.md. Whole-file reads take the glob. A section read finds the ## heading in whichever file holds it and stops at the next ## or the end of that file. Sites: tests/merge_test.sh:577-578, tests/epic_codex_test.sh:28 and :32, tests/epic_briefs_test.sh:317-318 (method.md plus the set; expected counts 2|2|2|0|1 unchanged), tests/skill_test.sh:60-62, tests/plan_epic_test.sh:15 and :112 (the default reads the set; $2 still names one file), tests/upgrade_test.sh:636-638, tests/command_names_test.sh:19-20. Add epic_briefs_test, plan_epic_test and upgrade_test to the floor of scripts/test-map.tsv:37's docs row: today `named` selects them only because their text names reference.md (scripts/test-map.tsv:4). This needs more than two mutation proofs, so prove them in a worktree copy without .git and say so in the PR.

**Done when:**
- scripts/select-tests.sh --run passes with all seven tests in its run.
- In the copy, moving ## Merging and ## Releases into a new docs/reference-zz.md keeps merge_test's § Merging check green, and deleting `swarm.sh merge` from that file turns it red.
- In the copy, a new docs/reference-zz.md holding a bare /swarm turns command_names_test red; one holding a log-finding line without --reviewer turns epic_codex_test red; one holding a 40+ character line of skills/swarm-dev/SKILL.md turns skill_test red.
- In the copy, deleting the clash-rule sentence from docs/reference.md turns epic_briefs_test red, deleting ## Scoping an epic turns plan_epic_test's method-section check red, and deleting every `swarm.sh upgrade` from the set turns upgrade_test red.
- scripts/test-map.tsv:37's floor names tests/epic_briefs_test.sh, tests/plan_epic_test.sh and tests/upgrade_test.sh, and tests/select_tests_test.sh passes.

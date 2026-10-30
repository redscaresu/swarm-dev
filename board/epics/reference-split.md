---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.30.0
depends_on: [delivery-liveness, lead-woken, merge-safety]
---

# reference-split

HLD Goal 10 (v0.31.0): no story clashes on docs/reference.md as a whole. Read where v0.29.0's 92 merge-ins fell, split the file by that evidence, and move the anchors, briefs and tests that name it in the same PR.

Moved into v0.30.0 by the user on 2026-10-29: in the v0.29.0 and v0.30.0 builds, docs/reference.md caused most merge-main conflicts and the repeated 'base merge unchecked' review loops (one PR went round four times). So it is built after the three epics now building, and before telemetry-readers, telemetry-writers and review-rounds-end are planned, which now depend on it. It is built alone, with no other story in flight, so its split meets no conflicting PR.

**Done when:**
- stage: v0.30.0 (moved from v0.31.0 on 2026-10-29, above).
- A reading of the merge commits that touched docs/reference.md in the v0.29.0 window, grouped by ## section (flow merge_ins' file-conflicts block, reports.sh:370-372, plus git log), is recorded in the story PR, and the split follows it: by ## command group when they fell across groups, or by new sub-headings inside Building (lines 845-1832) or Merging (2520-3329) when inside one (the file has 14 ## sections and no ###, contradiction 11).
- docs/reference.md becomes two or more files such that two in-flight stories touch two files; moved in the same PR: the eight anchors (README.md:130, 150, 173, 181, 184, 186, 249; AGENTS.md:83), the briefs naming reference.md § Building (build.sh:1504, 1511, 1753, 1786; merge.sh:1192; swarm.sh:384; board.sh:1339), llms.txt:11, skills/swarm-dev/SKILL.md:63, templates/docs/epics and stories READMEs, docs/method.md's (reference.md § X) pointers, commands/swarm.md:12 and 563.
- Tests that read it by heading or name pass: tests/merge_test.sh:577-578, epic_codex_test.sh:28-32, epic_briefs_test.sh:313, skill_test.sh:60, plan_epic_test.sh:15, upgrade_test.sh:636, command_names_test.sh:18, doc_check_test.sh; doc_check_test scans the new files (its regex reads docs/<file>.md one level deep, tests/doc_check_test.sh:42-53: widen it in the same PR if a subdirectory is used).
- docs/features.tsv row: conflict merge-ins caused by the reference files, read from `flow merge_ins`' file-conflicts block (92 of 194; bar under 10%).

**Out of scope:**
Rewriting content; splitting other docs; re-pointing existing board stories' touches (they name sections; later stories name the new files); the order in which the 0.28 epics are planned (release-v0-30-0 step 5, the lead's edit now).

**Constraints:**
- stage: v0.30.0, depends_on delivery-liveness, lead-woken and merge-safety (the front matter; moved on 2026-10-29, which overrides the HLD's v0.31.0 placement and its depends_on review-rounds-end and telemetry-writers, as those now depend on this epic). It runs before every v0.31.0 epic: machine-usable, merge-mechanics and deferred-700 depend_on it, and retro-gate, retro-report and handover-usage stay draft until its split PR merges (release-v0-30-0 step 5; contradiction 37).
- hooks/merge-guard.sh:65 names docs/reference.md in its block message: keep a docs/reference.md entry file so the hook text stays true, or that line is a protected-path lead-merged change.
- scripts/test-map.tsv covers docs/** (no row needed); tests/select_tests_test.sh requires every tracked docs file to map.
- A pure move needs no humanizer pass; reworded prose does.

**Areas:** docs/reference.md (split into docs/reference-<group>.md files or a docs/reference/ directory), README.md:anchors, AGENTS.md:83, llms.txt, skills/swarm-dev/SKILL.md:63, templates/docs/epics/README.md, templates/docs/stories/README.md, docs/method.md:(reference.md § X) pointers, bin/lib/build.sh:brief lines naming reference.md § Building, bin/lib/merge.sh:1192, bin/swarm.sh:384, bin/lib/board.sh:1339, commands/swarm.md:12 and 563, tests/doc_check_test.sh:scan regex, tests/merge_test.sh:577, tests/epic_codex_test.sh:28-32, tests/epic_briefs_test.sh:313, tests/skill_test.sh:60, tests/plan_epic_test.sh:15, tests/upgrade_test.sh:636, docs/features.tsv:Goal 10 row

**Your part:**
- When next prints stage v0.31.0, follow release-v0-30-0 step 5 as edited now: this HLD's six v0.31.0 epics go active in the stage PR; retro-gate, retro-report and handover-usage go active in a second board PR once this epic's split PR merges, so their stories' touches name the new files. Until then next's `stage v0.31.0` line for those three is expected: do not act on it.
- Merge by hand if the split changes hooks/merge-guard.sh:65.

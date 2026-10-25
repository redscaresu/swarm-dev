---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.30.0
depends_on: [review-loop, conductor-hands-off, less-noise, merge-holds, fixes-027]
---

# Generic rules reach every agent

Generic rules reach every agent: a rules file ships in the plugin, project_rules appends it before the project's brief, the builder brief and the review brief both carry its text with a test that fails when either drops it, and it holds Appendix B's generic engineering rules each with its why; review_checklist's overlapping lines fold into it. Appendix B's 'should be behaviour' items no other epic took become checks or reasoned drops. HLD Goal 3, Design § Memory extraction.

**Done when:**
- A rules file ships in the plugin, read from SWARM_HOME, and project_rules (bin/lib/build.sh:439-445) prints it before .claude/swarm/brief.md and the lesson: markers; story_brief (build.sh:396), review_brief (build.sh:792) and conduct_brief (build.sh:959) all carry it on a fixture project with no brief of its own.
- A test fails when the builder brief or the review brief drops the rules text (mutation proven in a copy of the worktree, Appendix C).
- The file holds Appendix B's thirteen generic engineering rules, each with a one-line why; review_checklist (build.sh:726-747, review-loop's by then) lines that overlap are folded into it so each rule has one source; no name tests/removed_test.sh:55-63 bans (lessons_report, rules_check_step, LESSON_).
- llms.txt and docs/reference.md name the file at its real path; README says a project gets new rules on claude plugin update; tests/llms_test.sh, tests/skill_test.sh, tests/doc_check_test.sh pass.
- Each of refill (an idle board is a trigger), time-boxed delegated work, a rebuilt story's From review items left uncommitted in the main checkout, syncing the main checkout never dropping board edits, and the humanizer on every human-facing command has a merged check, guard or next step with a test, or a reasoned drop recorded in the epic file for the retro to confirm.
- docs/features.tsv has a row for the rules file with metric `flow reviewers: findings of the kinds the rules name, per PR` and the 0.27 baseline from Appendix A's kind counts; the reading is the retro's.

**Out of scope:**
Project-specific rules (they stay in a project's brief or AGENTS.md); the retro's memory sort (retro-report); the swarm promoting a rule on its own.

**Constraints:**
- One mechanism, not a second: the file goes through project_rules, not a new brief source.
- Checks over prose: a rule that can be checked becomes a guard, test or next step, not a line in the file.
- tests/epic_briefs_test.sh and tests/review_test.sh are the places for the drop test; the review brief is review-loop's rewrite, merged before this stage.
- Rules reach the review agents that own the loop only once v0.30.0 is installed (builds run the installed plugin): no Done when here reads a live build.
- Touch docs/features.tsv as `docs/features.tsv:rules row`; bash 3.2, shellcheck, make test, claude plugin validate; humanizer over the rules file (people read it), README and docs.

**Areas:** a new rules file under the plugin root (path chosen by the plan, named in llms.txt), bin/lib/build.sh:project_rules, bin/lib/build.sh:review_checklist, llms.txt, docs/reference.md:briefs, README.md, docs/features.tsv:rules row, tests/ (epic_briefs, review, llms, doc_check), bin/lib or commands for the checks the five items become

**Your part:**
Appendix B's sort was agreed on 2026-10-25; a drop of one of the five behaviour items is confirmed by the user at the v0.31.0 retro. No other human step; the cut is the release story's.

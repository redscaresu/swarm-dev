---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: [stage-gating, test-speed, clash-by-part, no-agent-alert, liveness-signals]
---

# fixes-027

The four later stories epic-guard-gaps, plan-hld-gaps, small-fixes-027 and dash-grant-queue ship, and the two Appendix C and D gaps with no story (the dash_stalls BST failure, the dash lead-queue rows) are filed. HLD Goal 10 for this stage (Design § Less work names the four); the goal's check stays with retro-report. This epic's /plan-epic PR adopts the four (epic: set, status ready, touches rewritten as file:part), strikes small-fixes-027's two items no-agent-alert built and epic-guard-gaps' contents-reader item less-noise owns, each with the merged PR cited, and checks the fix-pin-ubuntu worktree item first (not present under swarm-dev-wt now) and closes it if gone.

**Done when:**
- epic-guard-gaps: a test for each remaining gap fails before and passes after (bin/lib/board.sh:620-640 epic_unticketed, next's draft-epic arm, commands/swarm.md lead_epics line).
- epic-guard-gaps' adoption keeps a staged flip passing: a board PR that sets a draft epic carrying stage: and hld: to active under an HLD that grants epics (epic_unticketed, bin/lib/board.sh:620-656) still merges through merge --board after the tightened flip and agreed: checks (board/stories/epic-guard-gaps.md:14-16); a test with a fixture staged epic fails if the flip is blocked, since the lead flips the v0.30.0 and v0.31.0 epics under the installed v0.29.0.
- plan-hld-gaps: a test for each of its nine gaps (commands/plan-hld.md, board.sh hld_due and plan_head, dash_render.py plan and finish rows, hooks/lead-stop.sh plan_drafted).
- small-fixes-027's remainder: the review_test flake, the rm -rf permission prompt, the loose-match lint missing =~, hld.md and epic.md step 5 board-pr worktree, dash_finished BOARD_OWN hld/, init updating an existing Board.base; each with a test or, for the flake, ten green runs cited.
- dash-grant-queue: under merge = human a PR whose HLD grants merge is not in the user's queue and a costs: money one is (bin/lib/dash_render.py awaiting rows); dash keeps the user's finish PR and 'awaiting your merge' out of the lead's queue under lead = session.
- tests/dash_stalls_test.sh passes between 00:00 and 01:00 BST (run under a faked local date past midnight).
- Each adopted story file is trimmed to what this epic built; the epic file records where each struck item went.
- /plan-epic splits a story that changes detection or alert logic, or is estimated over about 200 lines, before the board PR (v0.28.0 retro: select-tests-by-file took 7 review rounds and the no-agent alert stories 4 each).
- Planning briefs (plan-hld's hld-lead, plan-epic's lead) tell the agent to write its output file early and update it as it goes, so a timed-out turn loses one item, not all (v0.28.0 retro: a revision turn timed out after 68 minutes with nothing written).

**Out of scope:**
The protected-path hold, pinned-head reads and wait-pr (merge-holds); the contents-reader helper (less-noise); the two small-fixes items no-agent-alert built; changing what counts as a grant.

**Constraints:**
- Order: the epic-guard-gaps adoption goes after less-noise's contents-reader story and strikes the item; this epic's step-5 story (small-fixes-027's board-pr worktree item) and its plan-hld-gaps stories go after less-noise's codex-skip story, which edits the same paragraphs (commands/hld.md:79, epic.md:91, plan-hld.md:129); plan-hld-gaps' bare touches `commands/plan-hld.md` is rewritten as file:part on adoption, since under clash-by-part's rule a bare file never clashes with a part.
- hooks/lead-stop.sh edits are covered by tests/lead_stop_test.sh; a PR touching hooks/ waits for the user once merge-holds' hold is installed (v0.30.0), not during this stage.
- dash edits by tests/dash_test.sh and dash --check; plan-hld-gaps and dash-grant-queue both edit bin/lib/dash_render.py, touched as `dash_render.py:plan and finish rows` and `dash_render.py:awaiting rows`.
- Nothing a board sets is removed; a removed key warns and loads (tests/removed_test.sh:30-48).
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over commands/ and docs prose.

**Areas:** bin/lib/board.sh:epic_unticketed and hld_due and plan_head, commands/plan-hld.md, commands/hld.md and epic.md:step 5, commands/swarm.md:lead_epics line, bin/lib/dash_render.py:plan and finish rows, bin/lib/dash_render.py:awaiting rows, bin/lib/dash_finished.py, bin/lib/init.sh:Board.base, hooks/lead-stop.sh:plan_drafted, scripts/lint, board/stories (four adopted files), tests/ (review_test, dash_stalls_test, dash_test, grants_test)

**Your part:**
User: if any story turns out to remove something a board sets, you name every board that runs the plugin before it is filed (none planned). The cut is the release story's.

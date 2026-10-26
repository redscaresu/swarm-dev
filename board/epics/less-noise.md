---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: [stage-gating, test-speed, clash-by-part, no-agent-alert, liveness-signals]
---

# Less work and noise per story

Less work and noise per story: board-only PRs of three kinds skip codex, no incident for a wait on a busy agent, no nudge to a working agent, briefs show the guard's accepted forms, one helper each for the board-root path, the PR contents reader and the name cut, reconcile finishes merged stories the pull removed, and AGENTS.md carries the removal rule, the patch cadence, docs-move-with-behaviour and Appendix C's development rules. HLD Goal 9, Design § Less work, less noise and § Removing what a board sets.

**Done when:**
- A board-only PR of kind story-scope edit, hold or finish merges on green CI with no codex-review; a plan PR and an HLD agreement PR still run it. The kind is set where board-pr and codex-review are called (commands/hld.md:79, epic.md:91, plan-epic.md:37, plan-hld.md:129; bin/lib/merge.sh:270-278), not in scripts/board-only.sh; a test per kind. The retro-file kind is retro-report's, not this epic's.
- No `incident wait-timeout: busy` line is written when a wait times out on an agent that is working (bin/lib/agents.sh:1376); no nudge goes to an agent herdr reports working, on the path the 36 nudges took (the conductor's tell nudge at build.sh:977, 1101, 1127, checked first against events.tsv; tell_agent already dies on busy at agents.sh:1612); tests for each.
- Briefs show the forms the guard accepts (`cd <dir> || exit 1 &&`, swarm.sh merge alone, merge text only through the Write tool or a quoted heredoc) and say to wait with swarm.sh wait or wait-pr, never a hand-written loop; tests/merge_guard_test.sh is unchanged; this story names review-loop's brief story in depends_on.
- One helper for the board-root path replaces the inline copies (merge.sh:278, 556, 755, 790, 1299; board.sh:536, 635, 843, 1567; lifecycle.sh:84, 323, 1668; build.sh:307, 402); one PR-contents reader serves merge_read (merge.sh:141), pr_hld (board.sh:837) and release_check (merge.sh:1249); the herdr 32-char name cut matches only exact records (lifecycle.sh:1241-1246, 1305, 1462), with a refusal for a live agent under the cut. tests/close_exact_tab_test.sh and tests/close_test.sh pass and the old copies are gone.
- reconcile finishes a merged story whose file the main checkout's pull already removed: close_agent, clear_build and a `reconcile ... ok (finished)` event (board.sh:1564-1575 drop_gone_state today only drops state); tests/reconcile_pull_test.sh and tests/pr_removes_story_test.sh cover it.
- AGENTS.md carries: nothing a board sets is removed until every board the user runs is checked, and a removed key warns and loads for a release; a fix to the swarm's own loop ships as a patch release soon after it merges; docs move with behaviour in the same PR, which review_checklist (build.sh:726-747) names with the env: line as its example; and Appendix C's development rules (tests only through make, unset SWARM_PROJECT and no reports over days on the real repo, stress at most 4 CPUs torn down, mutation proofs in copies).
- Users can tell which workspace and tab is which, even with several swarms on one machine (user, 2026-10-26: users lost track, including users running more than one swarm). On 2026-10-26 two herdr workspaces were both labelled `kanban` (the lead's takes its folder's name, not the project's), conductor workspaces were named for the epic alone, numbers shifted as workspaces closed (test-speed went from 5 to 4), and agents the lead started (the HLD co-author, planners, a restarted builder at w20:p12) landed in the lead's own workspace. Now:
  - The workspace a swarm is started from, and its tab, are renamed `swarm-lead · <project>` when a swarm.sh command first runs from it (herdr workspace rename, herdr tab rename).
  - Each conductor's workspace is `<project> · <epic>` (backlog: `<project> · backlog`), so two swarms' epics never look alike.
  - Agents the lead starts outside an epic (the HLD co-author, planners, restarts) go to a `<project> · lead-agents` workspace, never the lead's own.
  - dash, status and a new `swarm.sh where <agent>` print each agent's workspace label and tab, not only its pane id; `swarm.sh dash --all` (or `swarms`) lists every swarm running on the machine: each project with a lead, and its conductors and agents.
  - A test per rule, with herdr stubbed, two projects in one fixture; the labels are documented in docs/reference.md and README.md.
- A merge = agent project is set up before its first conductor runs (v0.28.0 lesson: conductors were refused every merge as 'Merge Without Review', and the user merged 8 approved PRs by hand). `swarm.sh init` adds, or checks and names the user step for, an allow rule for `swarm.sh merge` in the user's Claude Code settings, and a preflight in `conduct` refuses to start with a clear message when the rule is missing under merge = agent. A test with the rule present and absent.
- Agents are not frozen by Claude Code's own UI (v0.28.0 lesson: the 'Teach auto mode' dialog and permission prompts froze at least six builder panes for hours, and answering one left a pane in manual mode). `init` tells the user to run auto mode's environment setup once and checks it was done; builders are told the command forms that need no approval (no unquoted globs in Bash). This epic adopts the story stuck-work-watch, which makes wait --lead alert on prompts, dialogs, manual mode and API-error stops, approved PRs left unmerged, and conflicts.
- The builder brief says to run only the selected tests (`scripts/select-tests.sh --run`) after review fixes and let CI run the full suite (v0.28.0 lesson: full local runs cost 30 to 60 minutes per round; #560 spent over an hour on two), and never to poll with a `pgrep -f` pattern that matches its own command line (v0.28.0: two such loops never ended). The brief test pins both lines.

**Out of scope:**
A guard on hand-written polling loops (rejected); changing the guard hook; the protected-path hold and the pinned-head reads (merge-holds); the four later stories (fixes-027); the retro-file board-PR kind (retro-report); fixing the stale env: line (a docs patch outside 0.28).

**Constraints:**
- ci_gate.py handles the board prefix in Python; the bash helper serves the shell sites and passes the prefix to Python.
- The contents-reader helper is this epic's; merge-holds' pinned-head story and fixes-027's epic-guard-gaps adoption name it in depends_on, and fixes-027 strikes epic-guard-gaps' contents-reader item.
- swarm-dev's AGENTS.md names no shared files (AGENTS.md:105-107), so its sections are ordinary story work touched as `AGENTS.md:<section heading>`.
- review_checklist (build.sh:726-747) is review-loop's: the docs-move-with-behaviour line goes in through a story that names review-loop's brief story in depends_on.
- tests/board_pr_test.sh and tests/board_only_test.sh cover the board-PR flow and CI gating; tests/removed_test.sh bans names (lessons_report, rules_check_step, ...) and pins removed keys warn and load.
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over AGENTS.md, README, docs and commands prose.
- Order: this epic's nudge story goes after conductor-hands-off's conduct_brief story (both edit green_rule and the nudge sites, bin/lib/build.sh:971-980, 977, 1101, 1127).
- Order: review-loop's self-close story goes after this epic's name-cut story (lifecycle.sh:1241-1246 is inside close_panes, :1231-1257) and after this epic's reconcile story (board.sh:1564-1575 adds a close_agent path review-loop tests).
- Order: fixes-027's step-5 story (small-fixes-027's board-pr worktree item) and its plan-hld-gaps stories go after this epic's codex-skip story, which edits the same paragraphs (commands/hld.md:79, epic.md:91, plan-hld.md:129).
- Order: conductor-hands-off's exact-name story goes after this epic's name-cut story; merge-holds' pinned-head story and fixes-027's epic-guard-gaps adoption go after this epic's contents-reader story.
- Order: this epic's AGENTS.md stories (two sections) go after review-loop's AGENTS.md review-agent line story (shared hot file, commands/plan-epic.md:69).

**Areas:** bin/lib/agents.sh:wait incident, bin/lib/build.sh:conduct_brief nudge sites and guard forms, bin/lib/merge.sh:board_root helper and merge_read and board PR kind, bin/lib/board.sh:pr_hld and drop_gone_state, bin/lib/lifecycle.sh:name cut sites, commands/hld.md, epic.md, plan-epic.md, plan-hld.md:codex-review call sites, AGENTS.md:Working on this repository, AGENTS.md:rules that are not negotiable, docs/reference.md:board PR kinds, docs/method.md, tests/

**Your part:**
Lead: land the docs patch for the stale env: line (AGENTS.md:97-98, README.md:123-124; the HLD says outside 0.28 and it is still stale at 71b2ab4) so the review check has its example; adopt the patch cadence from v0.29.0 on. The cut is the release story's.

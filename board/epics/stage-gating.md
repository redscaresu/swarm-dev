---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.28.0
depends_on: []
---

# The stage mechanism the HLD's Rollout relies on exists in the plugin

The stage mechanism the HLD's Rollout relies on exists in the plugin: `stage:` is a documented epic field, next prints `release` for a stage only when every epic of that stage has left the board and otherwise says fixes-only, next prints a `stage <v>` step after a stage's tag naming the draft epics to flip, staged drafts are not shown as `run /epic`, and the release arm says what each stage's release PR body must list. HLD Rollout § Stages, Non-goals (release PR lists behaviour changes and the infrafactory trial). No numbered goal.

**Done when:**
- board/epics/README.md and templates/docs/epics/README.md document `stage: v<x.y.0>` and that a staged draft epic is flipped active by the lead after the stage before it is tagged (tests/board_readme_test.sh keeps them matching); reference.md's epic front-matter section names it; doc_check passes.
- next's `release` arm (bin/lib/board.sh:281-283, release_due at :529-540) prints `release v<S>` only when no epic carrying `stage: v<S>` is left on the board, where S is read from the `stage:` of epic files deleted from origin/<base> since the last tag (git log on <board>/epics, since finished epics leave the board and finished story files are deleted, docs/reference.md:705); when a stage epic is still on the board it prints a `release-held: <stage>, open epics: <slugs>, patches only` line instead; when no epic carries stage: it prints as today. tests/next_test.sh pins all three on fixtures.
- After tag v<S> exists and draft epics carry the next stage, next prints `stage v<S+1>: set <slugs> active (board PR under the epics grant)` before any plan arm, and waiting_on_user (bin/lib/board.sh:979) lists a draft epic that carries stage: and hld: as `stage <v>, after <prev>`, never as `run /epic`; status and dash show the same; hooks/lead-stop.sh is not changed (an unknown step allows the stop, hooks/lead-stop.sh:9-11), recorded in reference.md; tests/next_test.sh and tests/dash_test.sh pin both.
- commands/swarm.md's release arm says a stage release is a minor, is cut only when next prints `release v<S>`, and that the release PR body lists the behaviour changes every project gets on upgrade and names the infrafactory build they were tried on or says none; tests/swarm_command_test.sh (or the test that pins the release arm) greps the three lines; command_names_test passes.
- commands/swarm.md has an arm for the new `stage v<S>` step: it opens the board PR that sets that stage's draft epics `active` (under the HLD's `epics` grant) and lands it, and a test fails if `next` can print a step that commands/swarm.md has no arm for.

**Out of scope:**
Changing commands/plan-hld.md (this HLD's later-stage epics are written draft by hand in the plan PR, Rollout § Stages; a future HLD with stages is a plan-hld change then); reading stage: in flow; the version rule itself (minor vs patch stays prose until retro-gate defines a fix in code); any change that stops a later-stage story merging early beyond draft status; the epic_unticketed path (bin/lib/board.sh:620-656 already accepts an hld: ticket under an HLD that grants epics, tests/merge_test.sh:1204-1236).

**Constraints:**
- Release stories: after this plan merges the lead files one kind: lead story per stage, release-v0.28.0 to release-v0.31.0, with no epic. The plan PR may only add epic files (commands/plan-hld.md:118-128), and a step in an epic's Your part becomes a lead story inside that epic (commands/plan-epic.md:67), which would keep the epic on the board until the cut and so hold the next stage through dep_holds (bin/lib/board.sh:517-524). Each release story covers: the cut with swarm.sh merge --release (the v0.31.0 one from main's bin/swarm.sh, after retro-v0.31.0, with the gate's output quoted); the release PR body, listing the behaviour changes every project gets on upgrade, naming the infrafactory build they were tried on or saying none, and quoting the previous stage's readings against their features.tsv bars (test_runs p90, ci_health, holds, merge_ins, lead_queue minutes, green_to_review_min, the PPID-1 check); **You:** restart the lead session (/exit, claude --continue); then the next stage's epics flipped active in one board PR under the epics grant. It starts when next prints `release v<S>`; for v0.28.0 the lead checks by hand that every v0.28.0 epic has left the board, since the installed 0.27.2 next prints `release` mid-stage.
- No front-matter schema check exists for epics (survey); do not add one that rejects boards without stage:.
- Nothing a board sets is removed (HLD Design § Removing what a board sets).
- Touch bin/lib/board.sh as `board.sh:next_step release arm`, `board.sh:release_due` and `board.sh:waiting_on_user`; no-agent-alert's next story names this epic's next story in depends_on (both edit next_step; AGENTS.md:105-106).
- release_due and merge --release apply to any project with a plugin.json and a v<version> tag (bin/lib/board.sh:530-539): a project with no stage: epics must see no change (the as-today case is tested).
- bash 3.2, shellcheck, loose_match_test, make test; humanizer over README, templates and commands prose.

**Areas:** bin/lib/board.sh:next_step release arm, bin/lib/board.sh:release_due, bin/lib/board.sh:waiting_on_user, commands/swarm.md:release arm, board/epics/README.md, templates/docs/epics/README.md, docs/reference.md:epic front matter and next steps, tests/ (next_test, dash_test, board_readme_test, the swarm.md release-arm test)

**Your part:**
In this plan PR the lead writes the v0.29.0 to v0.31.0 epics `status: draft` by hand and says so in the PR body (commands/plan-hld.md:108-113 would write them active). No other human step: the stage cut, the release PR, the restart and the flip belong to the per-stage release stories (constraints).

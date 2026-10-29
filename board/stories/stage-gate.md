---
kind: code
status: ready
epic: merge-safety
depends_on: []
touches: [bin/lib/board.sh:allowed_stage (new), bin/lib/lifecycle.sh:board_pr open (the stage check), bin/lib/merge.sh:epic_guard, tests/board_pr_test.sh:stage gate cases, tests/merge_rules_test.sh:stage gate cases, docs/reference.md:Staged epics paragraph (the stage gate), commands/plan-hld.md:Before the ask]
estimate_lines: 230
easy: false
risk: high
---

# board-pr open and merge refuse an epic set active above the stage the base allows

New allowed_stage in board.sh, beside epic_unticketed (the epic's constraint: no new guard, and idle_stage, board.sh:497, is not the rule), with the loop that applies it. Each <board>/epics/<slug>.md among the PR's paths goes active when it is status: active at the head (raw_status) and not active at the base, read with the caller's reader as epic_unticketed reads it. If its stage: is S (stage_of), it is refused unless S is allowed. S is allowed when the newest v<x.y.z> tag on origin/<base> (newest_tag, board.sh:1106) is at or above the minor before S (staged_draft's <prev>, 1065-1080; stage_due's rule, 1088-1100), or when an epic at origin/<base> that the PR does not change already has stage: S and status: active. An epic with no stage: passes. So does a v<x>.0.0 stage, which has no minor before it and goes through /epic (docs/reference.md:665-666). A malformed stage: is refused, naming it. The base is read in PROJECT_DIR after one fetch of the base branch with its tags, never from the PR. board-pr open has fetched it already (base_for, lifecycle.sh:147), and merge fetches it once per run. Both callers have the board in the project's repo (merge.sh:411, 874). The check is not inside epic_unticketed, whose first line exits under lead_epics = on (board.sh:1226), so it runs whatever lead_epics says; the story route reads no files with lead_epics on (merge.sh:411), as today. Callers: board_pr open, after its epic_unticketed (lifecycle.sh:163-164), dies with `board-pr: <slug> goes active at stage v<S>, above what <base> allows (newest tag v<T>, below v<P>, and no v<S> epic active there); commit it as status: draft: next's stage step sets it active once v<P> is tagged`. merge's epic_guard (merge.sh:309-321) merge_fails with the same why, under its --board: prefix on that route. Docs: the Staged epics paragraph (docs/reference.md:662-670) says board-pr and merge refuse it. commands/plan-hld.md's Before the ask (125-128) adds that an epic whose stage the base does not allow yet is written status: draft, whatever the grant says. Run humanizer over the prose. Skeptic review (2026-10-29). The refusal names the exit that exists: with an epics grant, next's stage step after v<P>; without one, run /swarm-dev:epic <slug> again once v<P> is tagged. A base with no v-tag counts as v0.0.0, so a v0.1.0 epic opens, and the line says no tag was found. A malformed stage: is refused. A v<x>.0.0 stage is refused until the base has a v<x-1>.y tag at or above the last minor the board staged, never allowed unconditionally. On the merge route the gate reads tags and active epics from the base through the same fetch merge_read uses, done lazily (only when an epic going active has a stage:), and a failed fetch refuses with its reason.

**Done when:**
- tests/board_pr_test.sh stage gate cases, each with a v-tag on the fixture's origin: the misread (a v0.31.0 epic set active, tag v0.29.1, v0.30.0 epics active on the base) is refused, and the line names the epic, v0.31.0 and v0.30.0.
- This HLD's plan shape (v0.30.0 epics set active beside v0.31.0 drafts, tag v0.29.1) opens.
- next's stage PR (tag v0.30.0, a v0.30.0 epic still active, v0.31.0 epics set active) opens.
- codex's interval (no v0.30.0 epic left, tag v0.29.1, a v0.31.0 epic set active) is refused. An epic with no stage: opens. A second v0.31.0 epic going active while one v0.31.0 epic is already active on the base opens.
- With lead_epics = on, the misread is still refused.
- tests/merge_rules_test.sh stage gate cases: merge --board of the misread refuses with `merge: --board: ` naming the epic, and the plan shape passes the guard.
- Copy-aside proof: reading 'already active' from the PR's head instead of the base turns the misread case red.
- shellcheck and tests/doc_check_test.sh pass.
- An agree PR for a no-grant v0.31.0 epic under tag v0.29.1 is refused and the line names /swarm-dev:epic.
- An untagged base lets a v0.1.0 epic go active and refuses v0.2.0; a malformed stage: is refused; v1.0.0 against a v0.29.x base is refused.
- Both refusals hold through merge --board too, with lead_epics = on as well; existing epic_guard --board cases pass unchanged.

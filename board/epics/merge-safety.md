---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.30.0
depends_on: []
---

# merge-safety

HLD Goal 8 and Design § Stage contents' check (v0.30.0): a merge of main that drops main's lines never reaches review or merge unseen (#693), with the user as the exit for a drop the builder answers in the PR; and board-pr and merge --board refuse an active epic whose stage is above the stage the base allows.

**Done when:**
- stage: v0.30.0
- `swarm.sh dropped-lines <owner/repo> <n> <head> <base>` (new, read-only): fetches refs/pull/<n>/head into the project's repo (repo_dir) and checks the fetched commit is <head> (a stale or moved head fails with a line; no worktree is read), lists every merge commit on the PR's first-parent chain base..head whose committer is not web-flow verified (merge_base_update validated those, merge.sh:544-548), runs `git show --remerge-diff` on each and prints every removed line that is in the merge's base-side parent's version of the file and not in its PR-side parent's: a base line the resolution dropped. Not printed: a line the PR's own non-merge commits removed, before or after the merge; PR-side lines the resolution dropped; conflict markers (false cases, each tested). With git below 2.36 it prints why and exits 2. Tests: two merges where the older one drops (caught); a clean merge; the PR-side drop; the stale fetch.
- merge_pr (merge.sh:830, after the CI gate at 893 and epic_guard at 899) runs it on the pinned head and holds a PR with output as `held: <slug> (dropped base lines: <n>, first <file>: <text>); the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand`, recorded as the protected-path hold is (merge.sh:786-800, protected_note) so lead_merge_shown (lifecycle.sh) prints it on the merge: line: the user is the exit for an answered drop (critic; contradiction 30). An exit-2 check holds too, saying why. A merge commit that drops nothing merges.
- The review side: a `dropped_lines_rule` line in review_brief has the review agent run the command before it reads the diff, on round 1 and after each `review-agent --next`, and when lines print, send them to the builder as the round's finding (a regression this PR introduces, which the cap keeps) and log it `log-finding --reviewer conductor dropped-lines`; review_at_head (build.sh:692-710) is not changed: its die reads as a failed start to no_review_events (lifecycle.sh:3144-3190) and would loop with delivery-liveness's retry (skeptic). Tests: the brief carries the line (tests/review_agent_test.sh:dropped-lines cases); a dropped-lines finding fires no no-review: line.
- Stage gate: board-pr open (lifecycle.sh:163-164) and merge --board's epic_guard (merge.sh:309-320), through epic_unticketed (board.sh:1223-1267), refuse a PR that sets an epic active whose stage: S is above the allowed stage, derived from the base and never from the PR: allowed when the newest v<x.y.z> tag on origin/<base> is at or above the minor before S (stage_due's rule, board.sh:1086-1100), or when an epic of stage S is already active on the base before the PR; an epic with no stage: passes. Tests: the misread (a v0.31.0 epic set active while the tag is v0.29.x and v0.30.0 epics are active) refused; this HLD's plan shape (v0.30.0 active beside v0.31.0 draft, tag v0.29.1) passes; next's own stage PR after the v0.30.0 tag with a v0.30.0 epic still active passes; codex's interval (v0.30.0 epics finished, tag still v0.29.x, a v0.31.0 epic set active) refused. commands/plan-hld.md:125-128 (Before the ask) says higher-stage epics are written draft; the v1 cite of :150-154 was wrong (contradiction 32).
- docs/lead-by-hand.md's #693 entry (73-80) removed; docs/features.tsv row for Goal 8: dropped-lines holds (metric `flow merges: holds by kind`, the column telemetry-writers adds; baseline 2 caught by hand) and, in the retro step board-loose-ends owns, `swarm.sh dropped-lines` rerun over every story PR merged since v0.30.0 with bar 0 (the bar's true reading; a hold count alone cannot show a slip).

**Out of scope:**
Any code in hooks/merge-guard.sh (protected; guard-main-checkout-edits owns check_git); GitHub's own update-branch merges (merge_base_update validates them); rewriting a builder's merge for it; the plan-PR hand check (the lead's, below); the flow column (telemetry-writers).

**Constraints:**
- stage: v0.30.0. Depends on no board epic: its parts (merge.sh:merge_pr dropped-lines step, lifecycle.sh:lead_merge_shown and board_pr open, board.sh:epic_unticketed and a new allowed_stage, build.sh:dropped_lines_rule and its one call in review_brief, tests/next_test.sh:stage gate cases, tests/merge_rules_test.sh, tests/review_agent_test.sh:dropped-lines cases) share no part with delivery-liveness or lead-woken. review-rounds-end depends_on this epic for build.sh:review_brief and the SERIAL tests/review_agent_test.sh (Makefile:18).
- The HLD cites merge.sh:533-538 as the CONFLICTING check; those lines are merge_base_update's 422 handling, the check is wait_pr (merge.sh:1989) and lifecycle.sh:2692 (contradiction 2).
- No hooks/ code: protected path, and guard-main-checkout-edits (rules-file, ready) owns it.
- A dropped-lines refusal is a hold with the line as exit, never a silent skip; the user clears an answered one by merging by hand, as for a protected path (merge.sh:786-800).
- The stage check lives beside epic_unticketed, not in a new guard; idle_stage (board.sh:497-506) is the lowest stage present whatever the status and is not the rule (contradiction 8).
- Protected-path and costs: money holds stay as they are.

**Areas:** bin/lib/merge.sh:dropped_lines (new command), bin/lib/merge.sh:merge_pr (dropped-lines step), bin/lib/merge.sh:epic_guard, bin/lib/lifecycle.sh:lead_merge_shown (the dropped-lines hold), bin/lib/lifecycle.sh:board_pr open, bin/lib/board.sh:epic_unticketed (stage check), bin/lib/board.sh:allowed_stage (new), bin/lib/build.sh:dropped_lines_rule (new) and its call in review_brief, bin/swarm.sh:dropped-lines dispatch arm and usage, commands/plan-hld.md:Before the ask (stage prose, 125-128), docs/reference.md:Merging (dropped lines), docs/reference.md:Decomposing an HLD (the stage check), docs/lead-by-hand.md:#693, docs/features.tsv:Goal 8 row, tests/merge_rules_test.sh, tests/merge_base_update_test.sh, tests/merge_base_moved_test.sh, tests/review_agent_test.sh:dropped-lines cases, tests/board_pr_test.sh, tests/next_test.sh:stage gate cases, tests/doc_check_test.sh (the new command)

**Your part:**
- For this HLD's own plan PR, before the gate exists: read each new epic's status: against its stage: (v0.30.0 active, v0.31.0 draft) before merge --board, and say so in the merge (HLD:308-310).
- A PR held for dropped base lines whose builder answered in the PR instead of restoring them is yours: read the answer, then merge by hand or tell the builder to restore the lines.

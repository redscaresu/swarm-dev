---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-tell]
---

# What follows a merge is Go: review, reconcile, the notes to conductors, and fix-main's writer

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) review and reconcile have markers; mark_review, reconcile, story_note, ready_tell, fix_main, clear_red_main and main_red_run are gone from bash (bin/lib/board.sh:3178-3650; bin/lib/merge.sh:1638-2242; bin/lib/lifecycle.sh:3796), and merge_pr and wait --lead, still bash, run the binary for them, `_fix-main` among them. (2) Every case of tests/review_test.sh, review_handoff_gaps_test.sh, reconcile_pull_test.sh, epic_reconcile_test.sh, merge_note_test.sh and retire_fixes_ancestry_test.sh gives the same lines, files and event lines. (3) Two reconciles at once take reconcile's lock one at a time, and two fix-main writers fix_lock, bash against Go and Go against bash. (4) A red main still gets one fix-main story and a green one clears it, from merge and from wait --lead.

**Out of scope:**
- merge_pr itself (port-merge)
- wait --lead's detached start of the fix-main run (port-lead-wait)
- Starting conductors for ready work, ported with next (port-next)

**Constraints:**
- Port rules P1 to P6 and P8.
- The notes go through tell (bin/lib/merge.sh:1686), which is why this depends on port-tell.
- fix-main has two callers, merge and wait --lead's `_fix-main` (bin/swarm.sh:721; bin/lib/merge.sh:1417). This epic owns all of it, so it never runs half in Go.
- Locks: reconcile's (bin/lib/board.sh:3528-3535) and fix_lock's file (bin/lib/merge.sh:2035,2195).
- reconcile, the notes and ready_tell run in the background of a merge (bin/lib/merge.sh:1359,1370,1429): the differential run compares their stub calls per step.
- About 1,370 lines: five port stories after two tests-only stories.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): one story is listed, the one that swaps merge_pr's own calls to review, reconcile, the notes and fix-main. The rest run after a merge and check none.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (review, reconcile, notes, fix-main)
- bin/lib/board.sh (mark_review to costs_diff)
- bin/lib/merge.sh (at_rev to main_red)
- bin/lib/lifecycle.sh (main_red_run)
- bin/ (marker files)
- tests/
- docs/reference-merging.md

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P2: The six port steps (HLD:250-262). A tests-only PR first rewrites the inside-reaching tests to drive swarm.sh from outside, passes on the bash, and shows each rewritten check can fail. The port PR then adds the Go, deletes the bash and Python it replaces, adds the command's marker file, repeats the mutation proofs on the Go, corrects every doc line that names a deleted file, and shows a clean differential run against the tree just before.
- P3: One copy of each rule (goal 3). When bash left behind still calls a ported rule, that bash runs the binary for it in the same PR, through a `_` entry.
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

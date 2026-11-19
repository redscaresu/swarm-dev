---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-merge-base, port-reconcile, port-release, port-wait-pr]
---

# merge is Go, on all three routes: a story PR, --board and --release

Then merge-refuse-red-base and protected-hold-grant land on the Go.

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) merge has its marker, and merge_pr with its checks, its lock and the merge queue is gone from bash (bin/lib/merge.sh:135-516,1081-1479,2242-2336). (2) On every case of tests/merge_test.sh, merge_rules_test.sh, merge_queue_test.sh, merge_protected_hold_test.sh, protected_hold_queue_test.sh, merge_lock_test.sh and merge_board_root_test.sh the Go refuses, holds or merges the same PR with the same line and exit code, on each route. (3) The differential run shows the same gh calls in order on the foreground path and within each background step, and no merge call on a held fixture. (4) Two merges at once take merge_lock one at a time, bash against Go included. (5) merge-refuse-red-base holds by its own Done when, as a fix: true story. (6) protected-hold-grant, as a fix: true story: under merge = human with a merge grant, a PR that changes hooks/, each other protected path, and each of the four Go package paths in the plugin's own repo is held, one case per path, which answers open question 1 with a fixture. (7) The lead has cut one real v0.32.x patch with `merge --release` in Go, and checked its files and the ref by hand.

**Out of scope:**
- The base update and dropped lines (port-merge-base)
- review, reconcile, the notes and fix-main (port-reconcile)
- The release checks (port-release)
- wait-pr (port-wait-pr)
- Changing what is held or refused, beyond the two items

**Constraints:**
- Port rules P1 to P8.
- merge's Go package is protected: the user merges every port here and every later change to it (HLD:297).
- merge_pr is one body for the three routes. It parses --board and --release itself, and the money hold, the head's CI check and the epic guard run on all of them (bin/lib/merge.sh:1194,1228-1290). So one port takes the name and all three routes, after everything it calls is Go: port-merge-base, port-reconcile, port-release, port-wait-pr and tell.
- merge_pr is about 290 lines in one function, at the story cap: it is one port story, with the checks before it in their own.
- It keeps every hold: the pinned head, green checks on the head, the base merged in when it moved, money, protected paths (protected_hold at bin/lib/merge.sh:418), dropped lines, the merge queue.
- protected-hold-grant's own Done when tests only a hooks/ fixture (board/stories/protected-hold-grant.md:15): the plan rewrites it with a case per path.
- merge_lock is at bin/lib/merge.sh:1081.
- The guard still refuses every merge but `swarm.sh merge`, in the form it accepts today.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): every story is listed, the two fixes among them. You clear them on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every port and fix in this epic (protected merge package).
- Lead: after the patch with merge's port, watch the first merges on the prerelease before more ports merge.
- Lead: cut the first patch with the Go release arm, and check its files and the ref by hand.

**Areas:**
- internal/merge
- bin/lib/merge.sh (ci_gate to merge_fail, merge_lock to merge_pr, queue_merge to within)
- bin/ (marker file)
- board/stories/merge-refuse-red-base.md, protected-hold-grant.md
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
- P7: A folded or deferred item is its own fix: true story after its command's port, with a test that fails on the old behaviour. The stage's differential run names it, with the exact lines it changes, among the fix: true differences (HLD:60-67). Its story file is rewritten: Go touches, epic:, fix: true, and no 'Python rewrite' text (HLD:314-316).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

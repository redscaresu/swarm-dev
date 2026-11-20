---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit]
---

# The helper the merge path and CI's gate rest on runs as Go: ci_gate, with poll_cache, which only it imports

CI's board-only gate still works.

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Both files are gone and every bash call site runs the binary (ci_gate is named on 78 lines of merge.sh, 19 of lifecycle.sh, 11 of board.sh and 4 of build.sh). While the Go is not yet run, a test runs each subcommand of both over the same recorded gh answers and compares output and exit code, and goes red when either side alone is changed. On the story that switches, the differential run is clean for the merge, wait-pr, review-agent, status and next fixtures. CI's board-only gate gives the same verdict on every case of tests/board_only_test.sh, the version-only release fast path among them, on the PR that deletes ci_gate.py and on the first PR after it.

**Out of scope:**
- Porting merge or wait-pr as commands (port-merge, port-wait-pr)
- dropped_lines.py (helpers-dropped-lines)
- Porting scripts/board-only.sh itself

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/merge_queue_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1 to P6 and P8.
- scripts/board-only.sh:58-59 runs bin/lib/ci_gate.py, and CI runs the base's copy of that script (.github/workflows/ci.yml:29-37): contradiction 4.
- ci_gate decides merges, so its Go and poll_cache's sit in the protected merge package and the user merges every port here.
- poll_cache's files under .swarm/ keep their format.
- ci_gate.py is 958 lines with one subcommand per call (head, base, fixed, required and more). The subcommands share gh, judge, checks and required (bin/lib/ci_gate.py:22,68,77,697) and the poll cache (:50,66), and none of that is on exception 3's list (HLD:278-281). So a group of subcommands cannot run as Go while the rest run as Python. The unit lands as Go that nothing runs, in stories under the cap, and one story switches every bash entry (ci_gate at bin/lib/merge.sh:135-137 and bin/lib/board.sh:1020, and the direct calls in board.sh, build.sh and lifecycle.sh) and deletes both files (P10; contradiction 24).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): every story is listed: ci_gate decides whether a head is green for merge. You clear them on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every port in this epic (protected merge package), and any change under .github/.

**Areas:**
- internal/merge (CI gate, poll cache)
- bin/lib/ci_gate.py, poll_cache.py (deleted)
- bin/lib/merge.sh, lifecycle.sh, board.sh, build.sh (ci_gate call sites)
- scripts/board-only.sh
- tests/

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P2: The six port steps (HLD:250-262). A tests-only PR first rewrites the inside-reaching tests to drive swarm.sh from outside, passes on the bash, and shows each rewritten check can fail. The port PR then adds the Go, deletes the bash and Python it replaces, adds the command's marker file, repeats the mutation proofs on the Go, corrects every doc line that names a deleted file, and shows a clean differential run against the tree just before.
- P3: One copy of each rule (goal 3). When bash left behind still calls a ported rule, that bash runs the binary for it in the same PR, through a `_` entry.
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P10: A story is capped at about 300 lines (commands/plan-epic.md:83). A unit that cannot be cut at a call boundary (the guard's parser, dash_render.py) lands as Go that nothing runs yet, in stories under the cap with Go tests, and the last story switches the caller and deletes the old code. Until then the old code is the only one that runs.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, port-board-readers]
---

# The release gates are Go: the patch gate with its three cases, the retro gate and the stage rule

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** release_due, release_stage, non_fix_change, retro_done and the stage functions are gone from bash (bin/lib/board.sh:1416-1866), and next and merge --release, still bash, get each answer from the binary. On every case of tests/non_fix_test.sh, retro_done_test.sh and the stage cases of next_test.sh the Go gives the same answer and line: a fix: true story, a fix-main build, a tests-only PR, a port: true PR with listed and with unlisted tests/ files, a minor with and without a done retro, a staged epic left on the board. An old session's bash and the Go read each other's gate cache. Each gh call is bounded.

**Out of scope:**
- merge --release itself and the docs gate (port-release, port-merge)
- next (port-next)
- Any new gate or case

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/non_fix_test.sh, tests/retro_done_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1 to P6 and P8.
- The Go sits in the protected release package: the user merges every PR here.
- non_fix_change's cache is keyed by its rule version, the board's path and both SHAs (bin/lib/board.sh:1590,1697). The Go keeps the key and the file's format.
- The gate reads git at the PR's commits, never the checkout (bin/lib/board.sh:1576).
- About 450 lines: two port stories after one tests-only story.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): every story is listed: they are the release gates. You clear them on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every PR in this epic and clear its stories on the board PR (HLD:480-485).

**Areas:**
- internal/release (gates)
- bin/lib/board.sh (release_due to stage_worktrees)
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

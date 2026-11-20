---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, board-store, helpers-flow-reviews, helpers-reports, helpers-ci-gate, helpers-dropped-lines]
---

# The board's shared readers and the small read-only commands are Go: config, policy, base and grants, with the story and epic graph the other commands read

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Each of the four commands has its marker and its bash is gone (show_config at bin/swarm.sh:373, policy at :446, base_for at :415, grants at bin/lib/board.sh:2548). Each prints the same on the fixtures (differential run clean). grants puts a PR that touches a protected path under no HLD, one case per path, the four Go package paths and `.claude-plugin/` in the plugin's own repo among them. Bash that still reads the graph (blocked_why, open_deps, waiting_on_user, costs) gets it from the binary. The harness shows none of the four starts python3, awk, sed or perl.

**Out of scope:**
- next and the release gates (port-next, port-release-gates)
- status (port-status). dash is deleted in stage 1 (delete-dash)
- Any new line or setting

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/roles_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1 to P6 and P8.
- This is the first command port, and all 60 helpers go before any command (HLD:266-268): it depends on every helper epic, directly or through another.
- The frame stays bash (binary-wrapper): these commands get the project and settings from it.
- grants reads pr_hld and protected_paths (bin/lib/board.sh:2461-2548). The protected list is a rule of merge: its Go sits in the protected merge package and the user merges that PR. The list carries over exactly, with a test per path.
- The `base` command is not in the HLD's stage list: contradiction 8.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): the story that carries the protected-paths list and the HLD over a PR (pr_hld) is listed, since both are rules of merge, and so is any story that edits merge_pr's own calls. You clear them on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge the PR that carries the protected list (protected merge package).

**Areas:**
- internal/ (board graph, config, policy)
- internal/merge (protected paths, the HLD over a PR)
- bin/lib/board.sh (board to epic_has_after, is_escalated to grants, waiting_on_user to open_pr)
- bin/swarm.sh (show_config, base_for, policy)
- bin/ (marker files)
- tests/
- docs/

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

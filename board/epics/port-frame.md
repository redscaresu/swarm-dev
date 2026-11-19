---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [loop-exit]
---

# What runs around every command is Go: the project lookup, the settings, the shim on PATH, the workspace label, the dispatch, the usage text and the outcome line

bin/swarm.sh only finds the binary and runs it.

Stage 4 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** bin/swarm.sh has no dispatch and no main and sources nothing: it finds the binary, fetches it if missing and runs it. Every command logs the same event line as before on the cases of tests/events_test.sh and the events_tail tests, a read-only command logs none, and an unknown command prints the same usage text and exits 2. SWARM_FORBID_PROJECT is refused with the same line, named directly and through a worktree. The lead's first command still labels its herdr workspace. status, next and dash still append their run-times row. doc_check and skill_test take the commands and settings from the Go, with the full count, and fail on none. The differential run is clean for every command, and CI's speed fixture shows none slower. The frame starts no awk to check SWARM_SLEEP_SCALE (bin/swarm.sh:120) or anything else outside the binary.

**Out of scope:**
- Deleting the three in-process bash helpers and the last scanners of bash text (bash-retired)
- Any new command or setting

**Constraints:**
- hooks/lead-session.sh goes here, with the bash that sources it (bin/lib/lifecycle.sh, lead_project and lead_rename's workspace label), not in port-hooks (codex).
- Port rules P1 to P6 and P8. No stage: line.
- This is the last seam between the two languages. The frame stayed bash, in one copy, while any command was bash (contradiction 15).
- About 600 lines of bin/swarm.sh are left by now (the header and usage, find_project, load_config's callers, dispatch, timed, main): two or three port stories after one tests-only story.
- The marker files go in the last story, with the lookup that read them.
- SWARM_SLEEP_SCALE keeps its check and message (bin/swarm.sh:120-121).
- The wrapper still runs on bash 3.2.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- bin/swarm.sh
- bin/ (marker files, deleted)
- internal/ (frame)
- tests/doc_check_test.sh
- tests/skill_test.sh
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

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, port-board-readers]
---

# The report commands are Go: flow, outcomes, dataset, retro, findings, lessons, and the three moved names cost, review-yield and features

Then retro-local-day lands on the Go.

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Each of the nine commands has its marker and its bash is gone from bin/lib/reports.sh and the dispatch. Each prints the same on the fixtures (differential run clean). The harness shows none starts python3, awk, sed or perl. After retro's port, retro-local-day's own Done when holds, in its own fix: true story, with a test that fails on the old behaviour and its named entry in the differential run.

**Out of scope:**
- log-finding and handover (port-board-writers)
- New flow sections or figures

**Constraints:**
- Port rules P1 to P8.
- The HLD's stage list does not name lessons, cost, review-yield or features: contradiction 8.
- out_of_scope_findings is also called by next's idle lines (bin/lib/board.sh:973-987): that bash runs the binary for it in the same PR.
- retro-local-day's story file is rewritten to the Go (today: touches bin/lib/reports.sh:retro window day, status later, no fix:).
- Run flow, outcomes, retro and dataset against the real repo once at most (AGENTS.md).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (reports)
- bin/lib/reports.sh (out_of_scope_findings to fail_lines)
- bin/ (marker files)
- board/stories/retro-local-day.md
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
- P7: A folded or deferred item is its own fix: true story after its command's port, with a test that fails on the old behaviour. The stage's differential run names it, with the exact lines it changes, among the fix: true differences (HLD:60-67). Its story file is rewritten: Go touches, epic:, fix: true, and no 'Python rewrite' text (HLD:314-316).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

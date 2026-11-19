---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit]
---

# The remaining small writers are Go: finish, reset, drop, hold, unblock, dialog, plan-unasked, log-finding, intervene and handover

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Each of the 10 commands has its marker and its bash is gone. On fixtures each writes the same files: front matter edits byte for byte, the same event lines, the same findings.tsv rows (differential run clean). handover writes the same folder. Writing front matter has one copy, in Go: bash that still writes it (set_fm, state_set, state_write) runs the binary. A bash writer and a Go writer on one story file never interleave under state_lock. The harness shows none starts python3, awk, sed or perl.

**Out of scope:**
- board-pr and init (port-board-pr)
- story, review and reconcile (port-story, port-reconcile)
- Removing any setting, field or brief form (HLD:463)

**Constraints:**
- Port rules P1 to P6 and P8.
- These are the stage list's 'remaining writers' (HLD:368). They do not run the loop, so they build beside the first loop ports.
- state_lock is at bin/lib/board.sh:3108; set_fm, state_set and state_write at :3073-3147.
- intervene's list of causes and log-finding's list of reviewers stay as they are.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (board writers, findings log, handover)
- bin/lib/board.sh (plan_unasked, unblock to state_write)
- bin/lib/handover.sh
- bin/lib/reports.sh (finding_flags, record_finding)
- bin/swarm.sh (intervene, hold)
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

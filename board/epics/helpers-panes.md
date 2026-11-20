---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, helpers-shared]
---

# The helpers that read panes and sessions run as Go: panes, session_mtime, longest_child, herdr_events, log_turn_over, usage_estimate, require_trusted, goal_entry, tidy_panes and status_report

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** None of the 10 files is left but panes.py, which stays under the comparison test until its last importer is ported. Each inline site the agreed list gives this epic calls the binary: the ones that import panes or session_mtime in agents.sh, lifecycle.sh and merge.sh:3274. tests/lib_path_test.sh's rule is kept by the check the agreed list names. The differential run is clean for every command that called them: agent starts, status, dash, wait, close, tidy. The harness shows those call sites start no python3. Each helper's mutation proofs are repeated on the Go.

**Out of scope:**
- The dash helpers and dash.sh's inline sites: deleted in stage 1 (delete-dash), not ported
- Porting any command's bash
- Changing how a stuck or stalled agent is told apart

**Constraints:**
- stall.py and stall_py.py are ported here too: they were helpers-dash's, which left the plan when the user chose on 2026-11-20 to delete dash (delete-dash) instead of porting it. Port them only once delete-dash has merged, and read which of their callers are left.
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/agent_state_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1 to P6 and P8.
- The inline sites embed Python that imports a helper through SWARM_LIB: contradiction 2. Each becomes a call to the binary, so this epic edits loop code that stage 3 ports later. The list in port-inventory says which sites are this epic's; readers-exit checks that none is left anywhere.
- Four sites also import report.session_log (bin/lib/agents.sh:1237,1251; bin/lib/lifecycle.sh:1178,4011), which is why this depends on helpers-shared.
- panes.py has 6 Python importers, dash helpers among them, and is on exception 3's list (HLD:278-281): its Python copy stays until its last Python importer is ported. stall.py is not on the list, and dash_age.py and dash_render.py import it. So stall.py, its entry stall_py.py and the site at dash.sh:700 leave this epic for helpers-dash: contradiction 24.
- These read herdr and session logs: they go through the agent runner interface, and herdr 0.9.2 stays the floor (bin/lib/agents.sh:174).
- No builder reads ~/.claude/projects or a session log by hand (rules.md:33); tests use fixtures.
- panes.py is 548 lines: two stories, cut by function.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none expected. The inline site at bin/lib/merge.sh:3274 is in watch_prs, which is no part of `merge`.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (panes, sessions)
- 9 of the 10 bin/lib/*.py files (deleted; panes.py stays)
- bin/lib/agents.sh, lifecycle.sh, merge.sh (the inline sites and call sites)
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
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

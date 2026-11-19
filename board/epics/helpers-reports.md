---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, helpers-shared]
---

# The helpers behind outcomes, dataset, retro and handover run as Go: outcomes_join, outcomes_rows, dataset, retro_report, the five retro_<name>.py files, handover.py and recurring.py

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** None of the 11 files is left. The differential run is clean for outcomes, dataset, retro and handover, and retro still prints one section per list in the same order. outcomes' recurring block and retro's recurring section name the same kinds as before on the fixtures. The harness shows those commands start no python3 for these helpers. handover still leaves out session logs, agent session ids and files named like a credential, shown by a fixture with one of each. Each helper's mutation proofs are repeated on the Go.

**Out of scope:**
- Porting the commands' bash (port-reports, port-board-writers)
- The retro-local-day fix (port-reports)

**Constraints:**
- Port rules P1 to P6 and P8.
- retro_report.py runs each bin/lib/retro_<name>.py by glob. It runs a ported section through the binary (helpers-shared) and goes in the story that ports the last retro section.
- recurring.py is on no exception list (HLD:278-281), and outcomes_join.py and retro_recurring.py import it. The three are one unit of 430 lines: their Go lands unrun in stories under the cap, and one story switches outcomes and retro's recurring section and deletes the three files (P10; contradiction 24). recurring imports report, whose Go is helpers-shared's.
- scripts/test-map.tsv has rows for the retro files and for handover: they change with the port.
- handover's rule for what it leaves out is an allowlist, never a denylist (rules.md:19).
- Never loop outcomes, retro or dataset against the real repo (AGENTS.md).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (outcomes, dataset, retro, handover)
- the 11 bin/lib/*.py files (deleted)
- bin/lib/reports.sh, handover.sh (call sites)
- scripts/test-map.tsv
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

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, helpers-shared, helpers-panes]
---

# The dash helpers run as Go, and the stall rule with them: dash_render, dash_slow, dash_age, dash_finished, dash_installed, dash_legend, stall and stall_py

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** None of the eight files is left, nor panes.py, whose last importers they were. `swarm.sh dash` draws the same screen on the fixtures, byte for byte, with SWARM_DASH_NOW fixed, and `dash --check` still agrees with each owning command. The three inline sites in dash.sh call the binary (bin/lib/dash.sh:119,700,747), and so does the stall rule's bash entry (stall_py, bin/lib/agents.sh:1540-1543), with the same answers on the stall cases the tests have (tests/dash_stalls_test.sh, epic_wait_session_test.sh and nudge_idle_test.sh among them). The differential run is clean for dash and wait. The harness shows dash and the stall rule start no python3 for these helpers. No dash_slow process is left after a test run.

**Out of scope:**
- Porting dash's bash (port-dash)
- Any change to what dash shows, or to its speed (HLD:90)

**Constraints:**
- Port rules P1 to P6 and P8.
- dash_render.py is 1,060 lines in one module and imports panes, stall, report, events_outcome, clock, dash_age and dash_legend. It is one unit over the 300-line cap: its Go lands first as code dash does not run, in stories under the cap with Go tests, and the last story switches dash to it and deletes the Python (contradiction 18).
- stall.py, dash_age.py and dash_legend.py are on no exception list (HLD:278-281), and dash_render.py imports all three. So none may run as Go while dash_render.py still runs. Their Go lands unrun beside dash_render's, and the one switch story moves dash, the three inline sites and stall_py's bash entry together and deletes those files and panes.py: contradiction 24.
- dash starts no detached refresh under tests, and dash's ci refresh honours SWARM_DASH_NOW (#1014).
- dash_installed takes the plugin's ID that release-client made swarm.sh read (bin/lib/dash.sh:551).
- Never run dash against the real repo in a loop (AGENTS.md).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (dash, stall)
- bin/lib/dash_*.py, panes.py, stall.py, stall_py.py (deleted)
- bin/lib/dash.sh (call sites, three inline sites)
- bin/lib/agents.sh (stall_py)
- tests/
- docs/dash.md

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

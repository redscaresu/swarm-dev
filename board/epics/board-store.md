---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit]
---

# Goal 3

The Go reads front matter and the config and appends event lines exactly as the bash does, and a test compares the two for as long as the bash copies stay.

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** A test runs the bash (fm, load_config, append_event) and the Go over every board file in the repo, every template, and a set of config and event fixtures that includes the malformed cases the bash tests have, and the outputs are byte-identical. It goes red when either side alone is changed. A story's state file is read before its front matter, as fm reads it. An unknown config key stops with today's message, and a REMOVED_KEYS key loads with the warning that names the key and its line. The Go appends an event line the way the bash does and refuses SWARM_FORBID_PROJECT.

**Out of scope:**
- Deleting the bash copies and the comparison test (bash-retired)
- Porting any command
- Writing front matter (port-board-writers)
- A YAML library (HLD:426-427)

**Constraints:**
- Port rules P1, P4, P5 and P6 (shared_constraints.port).
- Exception 1 (HLD:272-275): the bash copies stay until the last bash caller is ported, so these stories add Go and delete nothing.
- The parsers are our own and match the bash line for line: fm at bin/lib/board.sh:7 (state file, then front matter, and a report's snapshot), load_config at bin/swarm.sh:273 (key = value, no sourcing, CFG_ and SRC_ per key), append_event at bin/lib/agents.sh:983 with the outcome column's rule (bin/lib/agents.sh:969; tests/outcome_scan_test.sh).
- These packages are the store's one implementation (go-layers).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (front matter, config, events, store)
- tests/ (comparison test, fixtures)

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

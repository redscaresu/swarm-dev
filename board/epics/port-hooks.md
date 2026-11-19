---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-guard, lead-wait-fixes, port-board-pr, port-board-writers]
---

# The other four hooks and the gh shim are thin wrappers that run the binary: the lead's stop rule, the agent-state reports, the user-caught reminder and the gh call log

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) hooks/hooks.json is unchanged. Every case of tests/lead_stop_test.sh, agent_state_test.sh, user_caught_reminder_test.sh, gh_calls_test.sh and hooks_json_test.sh gives the same exit code, stdout, event lines and herdr and gh stub calls, and the hook differential run is clean for each on JSON-stdin fixtures. (2) lead-stop refuses a stop while next names a step not started, and allows it on any error and with no binary. agent-state reports each state to herdr in the background, SWARM_RESUME included. The reminder prints its context only in the lead's session. (3) The gh shim keeps exit codes, stdin, signals (INT gives 130), its log line and its log trim, and a failed log write never fails the call. With no binary it runs the real gh and never downloads, so the wrapper's own `gh release download` works through it. (4) No hook downloads or builds. From a worktree of a forbidden project the hooks write no event line. (5) The harness shows no hook and no gh call starts python3, awk, sed or perl, and each hook ends inside its timeout on CI's fixture.

**Out of scope:**
- The guard (port-guard)
- Changing hooks.json, or what any hook does
- Signing the binaries

**Constraints:**
- Port rules P1 to P6 and P8.
- hooks/ is protected: the user merges every PR that changes a hook file.
- lead-stop.sh allows the stop on any error (hooks/lead-stop.sh:26,34) and calls `swarm.sh _step`, Go since port-next. agent-state.sh runs under sh and backgrounds `herdr pane report-agent` (hooks/agent-state.sh:6-24).
- hooks/lead-session.sh is a wrapper since port-agent-starts. It stays after this epic: bin/lib/lifecycle.sh still sources it for lead_project, which lead_rename checks before it labels the lead's workspace, and that stays bash until port-frame. port-frame deletes it (codex).
- The shim is first on PATH for every swarm.sh call and every agent (bin/swarm.sh:229-233), and it becomes a process start of the binary per gh call: CI's speed fixture counts it. Its log trim is at bin/gh-shim/gh:113-121.
- Hooks load when a session starts, so an old session keeps the bash hooks until it restarts. Both write the same event lines.
- The wrappers run on bash 3.2, and agent-state's under sh.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none by its wording: the other four hooks and the gh shim are not the guard. You merge every PR that changes hooks/ anyway.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every PR here that changes hooks/.
- Lead: after each hook's patch, restart the sessions and check it in a live session before the next hook merges.

**Areas:**
- hooks/lead-stop.sh
- hooks/agent-state.sh
- hooks/user-caught-reminder.sh
- hooks/lead-session.sh
- bin/gh-shim/gh
- internal/ (lead stop, agent state, reminder, gh log)
- tests/
- docs/reference-lead.md (the stop hook)

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

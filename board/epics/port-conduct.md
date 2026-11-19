---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-story]
---

# conduct and codex-review are Go

Then calls-with-deadlines lands on the Go.

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Both have markers, and conduct_brief to start_conductor and codex_review with its fallback are gone (bin/lib/build.sh:1973-2496; bin/swarm.sh:777-1252). The conductor's brief is byte-identical on fixtures for an epic and for --backlog. A second conductor for one epic is still refused. On the cases of tests/codex_test.sh, codex_retry_test.sh, codex_rate_limit_test.sh and codex_unavailable_test.sh codex-review gives the same findings file, retries, limit and fallback lines, and it stops codex's process tree on a signal. On the lead's machine one story is built, reviewed and merged from the prerelease with story, review-agent and conduct in Go. Then calls-with-deadlines, as a fix: true story with three checks that each fail when their part is removed: a hung `claude agents`, `herdr agent list` or `herdr workspace list` stub returns within its bound; poll_while's grace is elapsed seconds, so a slow poll that keeps succeeding ends on time; and release_stage's gh calls end inside lead-stop's budget.

**Out of scope:**
- story and review-agent (port-story, port-review-agent)
- Changing a brief's text, or how codex is called

**Constraints:**
- Port rules P1 to P8.
- codex stays a subprocess found on PATH.
- codex-review kills by PID only the tree it started (kill_tree, bin/swarm.sh:784).
- It uses the brief rules port-story ported, which is why it depends on it.
- About 1,000 lines: four port stories after one tests-only story.
- calls-with-deadlines spans three ports: claude_agents (bin/lib/agents.sh:891, port-agent-starts), poll_while, whose one caller is codex-review's stop (bin/swarm.sh:833), and release_stage (port-release-gates). It lands here, after the last of them, not right after agent starts as the HLD's table has it (HLD:324).
- Its own Done when tests only the hung calls (board/stories/calls-with-deadlines.md:15). poll_while counts polls today and ignores how long each takes (bin/lib/agents.sh:1823-1828), and its release_stage part (#970) has no test: the plan rewrites the story with all three.
- It names tests/timeouts_test.sh, which scans bash text. Its list of bounded calls moves to the Go check the agreed list names (port-inventory).
- Its release_stage part changes the protected release package: the user merges that PR.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): calls-with-deadlines is listed, since it touches release_stage's bounds in the release gates. The rest are not.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge calls-with-deadlines' PR where it touches the release package.

**Areas:**
- internal/ (conduct, codex review, polling)
- internal/release (release_stage's bounds)
- bin/lib/build.sh (board_pr_merge_rule to start_conductor)
- bin/swarm.sh (is_command to fallback_brief)
- bin/lib/agents.sh (poll_while)
- bin/ (marker files)
- board/stories/calls-with-deadlines.md
- tests/
- docs/reference-building.md

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

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, port-lead-queue-prs]
---

# The other half of the lead's queue is Go: the lines about agents (stuck, reported, blocked on signing, at a prompt, missing, with no review, unsent, over the usage warning), and the queue's one entry

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** lead_queue and the functions that only read, from stuck_lines to usage_line, are gone from bash (bin/lib/lifecycle.sh:3505-3675,3852-5072), leaving what wait --lead starts (main_red_fix, review_restart, resend_pass). The lead's queue has one copy, in Go: status, wait --lead and dash get it from the binary. On the fixtures of tests/wait_lead_test.sh, no_agent_test.sh, stuck_work_watch_test.sh, queue_test.sh and idle_queue_test.sh each line is the same, byte for byte. The stuck, prompt and usage lines read panes through the agent runner.

**Out of scope:**
- wait --lead's loop and what it starts (port-lead-wait)
- The four folded items (lead-wait-fixes)
- Any new line

**Constraints:**
- Port rules P1 to P6 and P8.
- It owns lead_queue, the one function that puts the lines together, which is why it depends on port-lead-queue-prs.
- No builder reads a session log by hand (rules.md:33); tests use pane and session fixtures.
- Every line names its exit, and docs/reference-lead.md § The lead lists every line. None changes here.
- About 1,060 lines: four port stories after one tests-only story.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (lead queue: agent lines, the queue)
- bin/lib/lifecycle.sh (lead_queue to stuck_test_run, reported_lines to usage_warned, but main_red_fix, review_restart and resend_pass)
- tests/
- docs/reference-lead.md

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

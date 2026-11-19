---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit, port-next]
---

# The half of the lead's queue about PRs and merges is Go: the lines for open story PRs, their heads and bases, what waits on the user, plans and a red main

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** The functions from heads_green to plan_lines, and main_red_lines, are gone from bash (bin/lib/lifecycle.sh:2743-3505,3675-3722). status, wait --lead and dash, still bash, get these lines from the binary. On the fixtures of tests/wait_lead_test.sh, plan_lines_test.sh and unmerged_conflict_test.sh each line is the same, byte for byte, and the differential run is clean for status. A gh read that fails gives the same line as today, never an empty queue. Every gh call keeps its bound.

**Out of scope:**
- The lines about agents and the queue's one entry (port-lead-queue-agents)
- wait --lead's loop and what it starts (port-lead-wait)
- The four folded items (lead-wait-fixes)
- Any new line

**Constraints:**
- Port rules P1 to P6 and P8.
- status calls lead_queue (bin/lib/merge.sh:3659; bin/lib/lifecycle.sh:3505), which wait --lead and dash also call: contradiction 7. The queue is a rules package (HLD:166), so it reads gh and herdr only through the interfaces, and it moves to Go once, before status.
- Every line names its exit (docs/method.md § Who does what), and docs/reference-lead.md § The lead lists every line. None changes here.
- About 880 lines: three or four port stories after one tests-only story.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (lead queue: PR lines)
- bin/lib/lifecycle.sh (heads_green to plan_lines, main_red_lines)
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

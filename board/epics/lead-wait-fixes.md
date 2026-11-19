---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-lead-wait]
---

# The four items folded into `wait --lead` land on the Go: lead-stop-wakes, lead-queue-failed-read, no false `conflict:` line, and a builder left idle on an ended background run is noticed

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Four fix: true stories, each with a test that fails on the old behaviour and its named entry in the differential run. lead-stop-wakes and lead-queue-failed-read hold by their own Done when. No `conflict:` line is printed while GitHub has not yet said whether a PR merges, and one is printed once it says the PR conflicts. A builder left idle on an ended background run with uncommitted edits gives a line that names who clears it and how.

**Out of scope:**
- Any other new line
- hooks/lead-stop.sh (port-hooks)

**Constraints:**
- Port rules P1 and P4 to P7.
- The HLD lands each folded item right after its command's port (HLD:314). Two of the four change queue lines that are Go since stage 2; they still wait for wait --lead's port.
- The two deferred items have no story file yet: the plan writes them (2 of 2 `conflict:` lines on 2026-11-18 were false, HLD:323).
- The idle-builder item's shape is open question 3: its story settles it and the user agrees it there (HLD:554-555).
- Every line names its exit (docs/method.md § Who does what), and docs/reference-lead.md § The lead lists it.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You agree the shape of the idle-builder line in its story (open question 3, HLD:554-555). Nobody reads each story under the `stories` grant, so the lead lists this one on the board PR beside the carve-out's and waits for your go.

**Areas:**
- internal/ (lead wait, lead queue)
- board/stories/lead-stop-wakes.md, lead-queue-failed-read.md, two new story files
- tests/
- docs/reference-lead.md

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P7: A folded or deferred item is its own fix: true story after its command's port, with a test that fails on the old behaviour. The stage's differential run names it, with the exact lines it changes, among the fix: true differences (HLD:60-67). Its story file is rewritten: Go touches, epic:, fix: true, and no 'Python rewrite' text (HLD:314-316).
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

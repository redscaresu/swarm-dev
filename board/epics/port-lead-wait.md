---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-wait-agent, port-reconcile]
---

# `wait --lead` is Go: its loop, its locks, and what it starts itself

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** wait_lead and its loop are gone from bash (bin/lib/lifecycle.sh:5072-5346), with what it starts: the detached fix-main run, a review agent's next try and the resend of an unsent brief (main_red_fix, review_restart, resend_pass). The `_` name port-wait-agent left for it is gone. On every case of tests/wait_lead_test.sh, lead_handler_test.sh and unsent_brief_test.sh, and on the differential fixtures, it prints the same lines and ends the same way: `timeout:` exit 1, `replaced:` exit 143, `wait-failed: exit <rc>`. An old session's bash wait --lead and a new Go one still replace each other under lead_lock and pid_lock. A `no-review:` line still says `(started N of 3)`.

**Out of scope:**
- The lead's queue, already Go (port-lead-queue-prs, port-lead-queue-agents)
- The four folded items (lead-wait-fixes)
- hooks/lead-stop.sh (port-hooks)
- Any new line

**Constraints:**
- Port rules P1 to P6 and P8.
- It starts review agents, step-ups and the close of an idle pane as commands through swarm.sh (`review-agent`, `_step-up`, `_close-when-idle`; bin/lib/lifecycle.sh:4359), whichever side they run on.
- The fix-main run it starts is port-reconcile's, and a resend goes through tell: it depends on port-reconcile, which depends on port-tell.
- lead_lock and pid_lock (bin/lib/lifecycle.sh:5159,5236) are taken the same way.
- Every line names its exit, and docs/reference-lead.md § The lead lists every line.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.

**Areas:**
- internal/ (lead wait)
- bin/lib/lifecycle.sh (main_red_fix, review_restart_try to review_restart, poll_ps to resend_pass, lead_wake to wait_lead)
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

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit]
---

# wait-pr and watch are Go

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Both have markers and their bash is gone (wait_pr at bin/lib/merge.sh:2471, watch_prs at :3170, with the red-scan at :3435-3511). On the fixtures of tests/wait_pr_test.sh, wait_pr_cache_test.sh, wait_pr_expected_test.sh, wait_pr_new_head_test.sh, watch_cache_test.sh and watch_opened_test.sh each ends with the same line and exit code: wait-pr gives 0 green, 1 red, and 2 on a gh error, a conflict, no check runs, a workflow that never started within 5 minutes, a head that is not the given sha, or the timeout; `watch --epic` still prints `epic-done:`. The harness shows neither starts python3, awk, sed or perl.

**Out of scope:**
- wait <agent> and wait --lead (port-wait-agent, port-lead-wait)
- merge (port-merge)
- Changing any timeout or poll interval

**Constraints:**
- Port rules P1 to P6 and P8.
- Every CI wait goes through wait-pr, and the guard refuses a hand-written `gh pr checks` loop: wait-pr's forms stay.
- wait-pr reads ci_gate, Go since helpers-ci-gate, in the protected merge package; this epic adds no rule there.
- Sleeps honour SWARM_SLEEP_SCALE, and the binary ends on the same signals with the same exit codes.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none expected. A story is listed only if it edits merge_pr's own wait for CI.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- The story that ports wait_pr is listed too: merge_pr waits for CI through it on the head it made by merging the base in (bin/lib/merge.sh:763-778) (critic).

**Areas:**
- internal/ (wait-pr, watch)
- bin/lib/merge.sh (rate_reset to wait_pr, watch_scope to review_red_scan)
- bin/ (marker files)
- tests/
- docs/reference-merging.md

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

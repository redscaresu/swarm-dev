---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit, port-merge, port-upgrade]
---

# The guard hook is Go behind hooks/merge-guard.sh: every rule it has today, with no bash fast path and no python3

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) hooks/hooks.json is unchanged, and hooks/merge-guard.sh is a wrapper that finds the binary and runs it. (2) Every case of tests/merge_guard_test.sh and tests/guard_forms_test.sh gives the same exit code, the same `merge-guard: blocked (<form>)` message and the same event line, and the hook differential run is clean. (3) With no binary the hook refuses a command that says merge, in any project, and inside a swarm project a command that says one of the forms the guard blocks because they lose work: a cd joined by `;`, and git checkout, switch, restore, reset --hard, stash and clean. Each refusal is one line that says the guard cannot run and names the fix, `swarm.sh version`. The rest pass: pkill, killall, a `gh pr checks` loop and a bare `make test` among them, and a lose-work form outside a swarm project. One fixture file holds a command per lose-work form. The Go guard and the no-binary wrapper both refuse every line of it, and a test fails when the guard blocks a lose-work form the file lacks. The hook never downloads or builds, shown with an empty plugin folder and gh and go stubs that fail on any call. (4) After `swarm.sh update`, `upgrade`, an agent start or any other swarm.sh call the binary is there: a test makes a session's first Bash call after each and finds the guard running. (5) From a worktree of a forbidden project the hook writes no event line. (6) The harness shows the hook starts no python3, awk, sed or perl, with a binary and without one, and it ends within the time CI's fixture sets, on the first run after an update too. (7) Stage 3's allow list has the entry for the no-binary refusals: with no python3, v0.31.2 passed the commands that lose work (hooks/merge-guard.sh:43-45). With no binary and SWARM_AGENT set, the hook also refuses pkill, killall and `kill $(pgrep ...)`, which can end another session's process and lose its work (hooks/merge-guard.sh:17-19,37) (critic).

**Out of scope:**
- The other four hooks and the gh shim (port-hooks)
- Changing what the guard refuses when its binary is there
- Adding a timeout to the guard in hooks.json
- Signing the binaries

**Constraints:**
- Port rules P1 to P6 and P8.
- hooks/ and the guard's Go package are protected: the user merges every PR here.
- The guard is 45 lines of bash around one Python shell parser of about 700 lines (hooks/merge-guard.sh:47-752): contradiction 3. It is one unit over the 300-line cap, so its Go lands first as code no hook runs, in stories under the cap with Go tests of the parser, and the last story switches the hook and deletes the Python. Until then the Python is the only guard that runs (contradiction 18).
- The whole parser sits in internal/guard, not in a shared package (ship-gates).
- Its bash fast path (hooks/merge-guard.sh:30-45) goes, so every Bash tool call starts the binary (HLD:244-248).
- The guard hook has no timeout (hooks/hooks.json): a hung binary stalls every Bash call in every session with the plugin on.
- Every swarm.sh call fetches the binary (binary-fetch) and update runs the new wrapper once (release-client), so this epic edits no other epic's package. After Claude Code updates the plugin by itself, a session has no binary until some swarm.sh call. In that window the hook fails closed for a command that says merge or loses work (HLD:238-243; the user, 2026-11-19), under exception 2 (HLD:276-277).
- With no binary there is no parser and no reading of the tree as the guard reads it (hooks/merge-guard.sh:47-752). So the wrapper matches words, as the fast path does today (:33-41), and tells a swarm project the way the guard does (:2-4). It refuses more than the guard would, a safe `git checkout -b`, `stash list` or `clean -n` too, until a swarm.sh call fetches the binary: contradiction 25. The lose-work forms are the ones the guard's header names (:9-16).
- The wrapper's word match is bash alone. The fast path uses sed and tr today (hooks/merge-guard.sh:35), and bash-retired's test fails a hook that starts sed, awk or perl.
- Hooks load when a session starts, so an old session keeps the bash guard until it restarts. Both write the same event lines.
- The wrapper runs on bash 3.2.
- The docs say the guard needs python3 (docs/reference-merging.md:801,810,874; docs/reference-lead.md:644): they move with the port. README.md's update section gains the run-once step, and says what the hook refuses until then.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): every story is listed: all of them touch the guard. You clear them on the board PR, and with them the list of words the hook refuses with no binary.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every PR in this epic: hooks/ and the guard's Go package are protected.
- Lead and you: after any plugin update, run `swarm.sh version` once before other work. Until then the hook refuses by word, which is more than the guard would.
- Lead: once the switch has shipped, restart the sessions and check in a live session that a raw merge and a `git reset --hard` are still refused, before port-hooks starts.

**Areas:**
- hooks/merge-guard.sh
- internal/guard
- tests/
- docs/reference-merging.md
- docs/reference-lead.md (the guard)
- README.md (updating)

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

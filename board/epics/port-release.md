---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit]
---

# The release checks and the two commands that need no project are Go: the check of a version bump with the docs gate, the wait for a release's files, the plugin update, version and update

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** release_upgrade to docs_none are gone from bash (bin/lib/merge.sh:2632-3041), and merge's --release route, still bash, runs the binary for them. On fixtures a bump is refused with the same lines: more than the version changed; a patch with a change that is not fix, port or tests-only; a minor with no done retro; code changed with no doc and no `Docs: none` line. A release counts as done only once its files are attached and the ref has moved. The plugin update acts on the installed plugin's ID. `swarm.sh version` and `update` have markers, run with no project and start no python3 or curl; version keeps its time bound and reads the machine's own ref; update still ends by running the new version's wrapper once.

**Out of scope:**
- merge --release's route through merge_pr (port-merge)
- The gates' rules, already Go (port-release-gates)
- The release workflow (release-ci)
- upgrade (port-upgrade)

**Constraints:**
- Port rules P1 to P6 and P8.
- The Go sits in the protected release package: the user merges every PR here.
- It adds no second copy of the patch gate, the retro gate or the docs gate.
- release_upgrade runs each project's upgrade as the new version's own swarm.sh (bin/lib/merge.sh:2659), so it does not wait for port-upgrade.
- version and update are not in the HLD's stage list: contradiction 8.
- If a release through the Go fails, the lead can still cut one by hand: docs/lead-by-hand.md says how.
- Port rules P13 and P14.
- release_upgrade's port story is listed under the carve-out, as release-client's change to it was (critic).

**Your part:**
- Carve-out (HLD:480-485): every story that ports the release check, the docs gate or the release's confirmation is listed. The version and update story is not: neither is a gate. You clear the listed ones on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge every PR in this epic.

**Areas:**
- internal/release (release check, docs gate, confirm, plugin update)
- bin/lib/merge.sh (release_upgrade to docs_none)
- bin/swarm.sh (show_version, update_plugin)
- bin/ (marker files)
- tests/
- docs/reference-merging.md
- docs/lead-by-hand.md

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

---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [loop-exit, port-frame]
---

# Goal 1

No bash or Python is left under bin/ and hooks/ but the wrappers, and a user's machine needs no python3.

Stage 4 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** A test runs each of the 50 commands, the five hooks and the gh shim with python3, awk, sed, perl and curl on PATH replaced by programs that fail loudly, and all pass. It goes red when one command is made to call any of them. bin/lib holds no .sh and no .py. The bash copies of fm, load_config and append_event and their comparison test are gone, and the wrappers only find the binary and run it. README no longer asks users for python3. The shellcheck list (Makefile, ci.yml, AGENTS.md) and CI's py_compile step name only files that exist. scripts/lint has no python-clock rule. The three counts are zero outside the wrappers and scripts/ (lines of bash, lines of Python, python3 start sites), by a count the epic's last PR quotes.

**Out of scope:**
- The stage's exit: the user's go and the stable ref's move (retire-exit)
- Porting scripts/ (test.sh, select-tests.sh, select_tests.py, lint, board-only.sh, demo-dash.sh): contributors and CI keep python3 (HLD:99-101)
- Rewriting the bash tests in Go (HLD:97)
- The UI (v0.33)

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/port_tests_list_test.sh, tests/select_tests_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1, P2, P5, P6 and P8. No stage: line.
- scripts/select_tests.py walks bash call graphs (:52-53) and scripts/test-map.tsv's rows name bin/lib: both are cut down to the Go tree.
- The 17 tests that run on every bin/ change (scripts/test-map.tsv:26) include scanners of bash text. Each is retired only where the agreed list (port-inventory) names the Go check that took over its rule.
- The .github/, hooks/ and Makefile changes are protected.
- README.md:57 lists python3; AGENTS.md's tree and pre-PR commands name bin/lib.
- It removes no setting, field or brief form (HLD:463).
- The stage's exit is its own epic, retire-exit, as for every stage (HLD:352).
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none expected. A story that edits hooks/merge-guard.sh is listed.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge the PRs that change .github/, hooks/ or the Makefile.

**Areas:**
- bin/lib/ (deleted)
- bin/swarm.sh (the wrapper)
- hooks/
- README.md
- AGENTS.md
- Makefile
- .github/workflows/ci.yml
- scripts/lint
- scripts/test-map.tsv
- scripts/select_tests.py
- tests/

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P2: The six port steps (HLD:250-262). A tests-only PR first rewrites the inside-reaching tests to drive swarm.sh from outside, passes on the bash, and shows each rewritten check can fail. The port PR then adds the Go, deletes the bash and Python it replaces, adds the command's marker file, repeats the mutation proofs on the Go, corrects every doc line that names a deleted file, and shows a clean differential run against the tree just before.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.

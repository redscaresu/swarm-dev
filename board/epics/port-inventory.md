---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [ship-gates]
stage: v0.32.0
---

# Goal 8, and the two lists every port is checked against: the agreed list of tests and inline sites that reach inside the code, and the inventory a reviewer reads a port with

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) The list names every tests/*_test.sh that sources bin/lib, runs or names a .py helper, reads source text or stubs python3, each marked rewrite-from-outside or becomes-a-Go-test, and the user has agreed it. (2) It names each inline `python3 -c` site that imports a helper, by file and function, with the one epic that rewrites it, and a test fails when such a site exists that the list lacks. (3) The inventory lists every SWARM_* name the code reads, every lock file with its protocol, each command's exit codes, and every command, setting, field and hook path of v0.31.2. A test fails when the code reads a SWARM_* name or takes a lock the inventory lacks, and when a v0.31.2 name is gone.

**Out of scope:**
- Rewriting any test: each port epic rewrites its own
- Rewriting the tests in Go (HLD:97)
- The differential run, the speed fixture and the python3 harness (port-checks)

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/port_fields_test.sh, tests/port_locks_test.sh, tests/port_swarm_names_test.sh. Each keeps the assertion its go_check column names.
- stage: v0.32.0.
- The list replaces the HLD's 46 to 67 range. At 171c1dbf, 32 of 208 test files name a bin/lib/*.py and 25 source a bin/lib/*.sh.
- The list also covers the tests that read bin/ and hooks/ as text (loose_match, timeouts, outcome_scan, lib_path, agent_state, removed, command_names, doc_check, skill, events_fixture) and names the Go check that keeps each one's rule.
- There are 25 inline import sites at 4dab0503: 12 in agents.sh, 7 in lifecycle.sh, 3 in dash.sh, 1 in merge.sh (:3274), 1 in bin/swarm.sh (:859) and 1 in board.sh (:1703). The last sets its path from an argument, not SWARM_LIB, so the test finds a site by its import, however the path is set. A site that imports two families goes to the later epic of the two.
- The inventory counts lock files, not functions: contradiction 9. Locks are mkdir(2) through perl because uutils mkdir lets two racers win (bin/lib/board.sh:3111). The code reads 126 SWARM_* names.
- The inventory also lists the bash plumbing that is no rule and keeps its copy beside a Go counterpart until its last bash caller is ported: die, within (called at about 155 places), scaled, nap and json. The list is closed, so nothing else may claim that leave (contradiction 15).
- Each new check is shown able to fail, on a copy of the worktree without .git (AGENTS.md; rules.md:25).
- The list and the inventory are docs under docs/: they go through the humanizer.

**Your part:**
- You agree the list of inside-reaching tests and which few become Go tests (HLD:97-98,285-286): a kind: lead story with a You: step.
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.

**Areas:**
- docs/ (inventory, test list)
- tests/ (the two tests)

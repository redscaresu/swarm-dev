---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core]
needs: diff-run-core (tests/diff_run.sh's fixture loader, which builds each listed command's project)
touches: [tests/nopy_test.sh, tests/nopy_list.txt, AGENTS.md:python3 harness paragraph (Working on this repository)]
estimate_lines: 150
---

# A test goes red when a listed command starts python3

Uses diff-run-core's fixture loader. tests/nopy_test.sh runs each fixture on tests/nopy_list.txt. Each line names a fixture and the programs it must not start: python3 at stage 1, then awk, sed, perl and curl as port epics list them. For the command's run only, each named program is replaced on PATH by a stub that logs its argv and exits 1 with a loud stderr line. The fixture build keeps the real one, since merge_fixture.sh's helpers use python3. The test is red when the log has a line for a listed fixture, so a command that swallows the failure is still caught. It catches a program found on PATH; one started by its absolute path is out of its reach, and the header says so. The list starts with the seed and hook fixtures that start no python3 on main today, which may be none: append_event reads the version through python3 (bin/lib/agents.sh:970-985; bin/swarm.sh:133). It runs under make test, so no CI file changes. AGENTS.md gains a paragraph on tests/nopy_list.txt for port epics.

**Done when:**
- (1) On a worktree copy without .git, a listed command made to run `python3 -c 1 || true` fails the test, naming the command and the program. (2) A listed fixture that starts no python3 passes. If main's list is empty, the test runs one fixture of its own and prints that the list is empty. (3) A program named for one fixture is stubbed for that fixture only. (4) A fixture whose build runs python3 and whose command does not passes. (5) The test runs in under 120 s on its CI shard.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/tests.tsv, tests/port_tests_list_test.sh]
estimate_lines: 230
---

# docs/port/tests.tsv lists every test that reaches inside the code, with the Go check and owner for each text scanner, and a test fails on one it lacks

Needs no other story.
- Write docs/port/tests.tsv. `#` header lines name the columns (file, reach, mark, go_check, epic) and state the rule. One row per tests/*_test.sh that reaches inside the code. reach is the comma-separated kinds that apply:
  - lib: sources a bin/lib/*.sh, directly or through a tests/*.sh helper that does (tests/merge_fixture.sh:304 sources agents.sh in a bash -c; 16 tests source that fixture);
  - py: names a bin/lib/*.py file or runs a helper module;
  - text: reads a file under bin/ or hooks/ as text (grep, sed, awk, cat or open() on it, or parses dispatch or CONFIG_KEYS);
  - python3-stub: puts a python3 stub on PATH.
- Pre-seed rows for the tests other stories add, so either merge order stays green: tests/port_sites_test.sh, port_swarm_names_test.sh, port_locks_test.sh, port_names_test.sh and port_fields_test.sh (this epic's wave 1; each reads bin/ as text), and tests/nopy_test.sh (port-checks' nopy-harness, .swarm/port-checks/lead.json; a python3 stub). A row whose file is not there yet passes. If the rule finds this story's own test, give it a row too.
- mark: rewrite-from-outside or becomes-a-Go-test. Only a few become Go tests (HLD:97-98). Propose the marks; the user agrees them in port-tests-agree.
- go_check, on every text row (loose_match, timeouts, outcome_scan, lib_path, agent_state, removed, command_names, doc_check, skill, events_fixture, the pre-seeded five and any other the rule finds): the Go check that keeps its rule once the bash it reads is gone, said as what it asserts, and in epic the slug that adds it. Where the rule's subject ends with a port (no inline site can exist in Go), write `retired-with: <epic>`. Never empty or a placeholder. Proposed owners: binary-wrapper for the tests that parse dispatch or CONFIG_KEYS (its Done when (6) already covers doc_check and skill_test, board/epics/binary-wrapper.md:14); port-inventory for port_swarm_names, port_locks and port_fields, which scan Go from the start; go-layers only for the import and clock checks (board/epics/go-layers.md:14). The PR quotes a check that each owner has a board/epics file at the base. The user agrees the owners in port-tests-agree.
- epic, on a row with no go_check: the first port epic, in stage order, that deletes code the test reaches (command_owner and helper_owner in .swarm/2026-11-18-swarm-dev-v0-32-go-rewrite-prior/hld-lead-v2.json).
- Add tests/port_tests_list_test.sh. It applies the same rule to tests/*_test.sh. It fails, naming the file and its reach, on a file with no row; on a mark that is neither of the two; and on a text row whose go_check or epic is empty, `none`, `none yet`, `tbd`, `?` or `-`. It does not check that the owner's file exists: a finished epic's file is deleted (#1000 deleted board/epics/retro-report.md). A row whose file the rule no longer finds passes: the list is the record. Each failure line names docs/port/tests.tsv and the row to add, so a builder in another epic knows the fix. Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git.
- Prove it red on a copy of the worktree without .git: a new test that sources bin/lib/board.sh, one that sources tests/merge_fixture.sh, one with a python3 stub, a deleted row, and a text row whose go_check is `none yet`. Say so in the PR.
- The PR gives the count with its population: N of the tests/*_test.sh at the base, per reach kind. The HLD's 46 to 67 and the epic's 25 and 32 came from other rules (survey).
- Humanizer over the PR body and the header lines.

**Done when:**
- tests.tsv has one row per tests/*_test.sh the stated rule finds at the story's base, plus the six pre-seeded rows, each with a mark; every text row names a go_check and an owner epic, and no row has a placeholder. tests/port_tests_list_test.sh passes on the branch and goes red on each of the five seeded cases on a copy without .git, each failure naming tests.tsv.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [docs/port/copies.tsv, tests/port_copies_test.sh, docs/port/tests.tsv:port_copies row, docs/port/README.md:§ What each list holds, scripts/test-map.tsv:port_copies row]
estimate_lines: 240
---

# A list names what still imports each of the five Python copies, and a test fails a copy that outlives its last importer or goes before it

The epic's Done when (4). docs/port/copies.tsv: one row per module, importer and kind, for clock, events_outcome, report, touches_rows and gh_cache. The kinds: py, a bin/lib/*.py file that imports it, lazy imports included (touches_rows.py:182, handover.py:34); site, an inline python3 -c or heredoc in bin/ or hooks/, this epic's four and helpers-panes'; script, bash running the module file (touches_rows.py at bin/lib/build.sh:1957 and bin/lib/board.sh:909); test, a tests/*.sh that imports it. tests/port_copies_test.sh recomputes the importers by that rule, over the tree or over a root it is given, so it can check itself on a fixture tree. It fails on an importer with no row, a row whose importer no longer imports, a module whose rows remain once its .py file is gone, and a module file left with no rows. Its header states the counting rule, and the PR quotes the count per module and kind. The test gets rows in docs/port/tests.tsv and scripts/test-map.tsv, and README.md § What each list holds gains the list.

**Done when:**
- (1) tests/port_copies_test.sh passes on the tree. (2) On a worktree copy without .git, it goes red with a line naming the module and the importer for each of: a new `from report import pr_key` in a bin/lib file; a row whose importer's import is removed; events_outcome.py deleted with its rows left. (3) A case in the test runs the check over a fixture tree that keeps a module's file while its last importer and that importer's row are both gone, and expects the line for a module left with no importer. With only that check removed, the case goes red, shown on a worktree copy without .git. (4) tests/port_tests_list_test.sh passes with the new test's row. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: chore
status: blocked
epic: port-inventory
depends_on: [port-tests-list, port-sites-list, port-swarm-names, port-locks, port-frozen-names, port-frozen-fields, select-tests-go]
needs: port-tests-list (tests/port_tests_list_test.sh); port-sites-list (tests/port_sites_test.sh); port-swarm-names (tests/port_swarm_names_test.sh); port-locks (tests/port_locks_test.sh); port-frozen-names (tests/port_names_test.sh); port-frozen-fields (tests/port_fields_test.sh); select-tests-go (the Go row in scripts/test-map.tsv and the Go-only branch case in tests/select_tests_test.sh (go-module, .swarm/go-module/lead.json))
touches: [scripts/test-map.tsv:bin rows' floor, scripts/test-map.tsv:gh-shim row, scripts/test-map.tsv:hooks row, scripts/test-map.tsv:Go row floor, scripts/test-map.tsv:tests rows, tests/select_tests_test.sh:floor arrays, tests/select_tests_test.sh:Go-only branch case floor]
estimate_lines: 40
easy: true
---

# select-tests.sh runs each new list test on a change to any path it scans

Uses tests/port_sites_test.sh, port_swarm_names_test.sh, port_locks_test.sh, port_names_test.sh, port_fields_test.sh and port_tests_list_test.sh from the stories that add them. Also uses the Go row `go.mod go.sum cmd/** internal/**` that select-tests-go (go-module) adds to scripts/test-map.tsv.
- Before you edit: scripts/test-map.tsv at your base must have that Go row. If it does not, stop and tell the conductor: a depends_on slug with no story file counts as finished (bin/lib/board.sh:2819-2826), so the edge may not have held.
- These tests read files through a glob and name none, so select-tests.sh never picks them for a change to what they scan. Add each to the floor of every row for a path family it scans:
  - the three bin rows (bin/lib/retro_*.py, the handover row, and bin/swarm.sh bin/lib/*.sh bin/lib/*.py): port_sites, port_swarm_names, port_locks, port_names, port_fields;
  - bin/gh-shim/gh (test-map.tsv:31) and hooks/* (:41): port_sites, port_swarm_names, port_locks, port_names;
  - the Go row: port_swarm_names, port_locks, port_fields;
  - tests/*_test.sh (:50) and tests/*.sh (:52): port_tests_list.
  Update each row's comment.
- templates/ needs nothing: no row matches it and check_map does not look there (scripts/select_tests.py:45), so a template change already selects every test.
- tests/select_tests_test.sh copies the real map (:55) and pins each floor exactly (:46-50; its cases say `no other`). Add the new tests to BIN_FLOOR, SHELL_FLOOR (which SHIM_FLOOR extends) and TEST_FLOOR, and to the Go-only branch case select-tests-go adds. That test is the red proof: on a worktree copy, drop port_locks from the hooks row and it goes red.
- `scripts/select-tests.sh --check-map` and tests/select_tests_test.sh pass.

**Done when:**
- For a change to bin/lib/agents.sh, bin/gh-shim/gh, hooks/merge-guard.sh, internal/x/y.go, tests/merge_fixture.sh and tests/x_test.sh, select-tests.sh's list names each new test that scans that path, and the PR quotes the six lists. tests/select_tests_test.sh passes, and goes red on a worktree copy with port_locks dropped from the hooks row.
- scripts/select-tests.sh --run passes

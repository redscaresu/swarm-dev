---
kind: lead
status: blocked
epic: port-inventory
depends_on: [port-tests-list]
needs: port-tests-list (docs/port/tests.tsv, its proposed marks and go_check owners)
touches: [docs/port/tests.tsv:mark column, docs/port/tests.tsv:go_check column, docs/port/tests.tsv:header lines, board/epics/<each owning epic>.md:Constraints go_check line]
estimate_lines: 20
---

# You agree the list of inside-reaching tests, which few become Go tests, and who owns each Go check

Uses docs/port/tests.tsv, with its proposed marks and go_check owners, from port-tests-list.
- **You:** read docs/port/tests.tsv. Agree it or change marks, and say which few tests become Go tests (HLD:97-98,285-286). Agree or change the epic that owns each text row's go_check.
- Lead: apply the answer to docs/port/tests.tsv in one PR, with a header line `# agreed by the user on <date>`. In the same PR, add one line to the Constraints of each epic the go_check column names, listing its rows, so its planner builds the check. Merge it with `swarm.sh merge` once green.

Read each row's owning epic from the list's `epic` column, not from `go_check`, which holds the assertion to keep or a `retired-with:` note (codex).

**Done when:**
- tests.tsv on main carries the user's marks and owners and the date they agreed it, and tests/port_tests_list_test.sh passes on that commit. Each owning epic's file names its go_check rows.

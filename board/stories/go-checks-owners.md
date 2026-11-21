---
kind: lead
status: blocked
epic: binary-wrapper
depends_on: [name-readers-markers, go-frame-entry]
needs: name-readers-markers: tests/swarm_commands.sh and the four tests that read the markers, which rows 44, 107 and 131 describe; go-frame-entry: the Go test that pins the table to the markers, which those rows name
touches: [docs/port/tests.tsv:config_test row, docs/port/tests.tsv:doc_check_test row, docs/port/tests.tsv:events_test row, docs/port/tests.tsv:port_names_test row, docs/port/tests.tsv:skill_test row, docs/port/tests.tsv:header lines, board/epics/binary-wrapper.md:Constraints go_check line, board/epics/board-store.md:Constraints go_check line, board/epics/port-frame.md:Constraints go_check line]
estimate_lines: 15
easy: true
---

# You agree who builds the Go checks this epic cannot build without a second copy of the frame

Uses name-readers-markers' tests/swarm_commands.sh and go-frame-entry's Go test pinning its table to the markers, which the reworded rows describe. The epic keeps six go_checks (binary-wrapper.md:24) and keeps one copy of the frame (:26). Three go_checks need a Go copy of something the frame still owns: config_test's Go config package (docs/port/tests.tsv:34; none until board-store ports load_config), doc_check's Go settings list (:44; the same package), and events_test's Go read-only set (:63; READ_ONLY_COMMANDS stays in bash main until port-frame). Three name the Go dispatch table (doc_check's commands half :44, port_names :107, skill_test :131): here they read the markers, which the Go test pins to the table. **You:** agree, or change: config_test and doc_check's settings half go to board-store; events_test and the Go-table reads go to port-frame; the markers stand in for the table until then. The answer can come on the board PR. Lead, after both stories merge: one PR applies it. Rows 34, 44 and 63 get their new epic, rows 44, 107 and 131 say what binary-wrapper built, and a header line dates the change. The go_check lines of binary-wrapper.md, board-store.md (:22) and port-frame.md (:20) name their rows, as port-tests-agree did. Merge it with swarm.sh merge once green.

**Done when:**
- docs/port/tests.tsv on main gives rows 34, 44 and 63 the epics the user agreed, with the date, and tests/port_tests_list_test.sh passes on that commit.
- binary-wrapper.md's go_check line lists only the checks this epic built, and board-store.md's and port-frame.md's go_check lines name each row they took.

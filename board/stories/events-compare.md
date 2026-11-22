---
kind: code
status: later
epic: board-store
depends_on: [events-append-go]
needs: events-append-go: the Appender, with the time passed in, the plugin root set and the write error returned
touches: [internal/events/bash_compare_test.go (new), internal/events/testdata/ (new), docs/port/tests.tsv:internal/events row]
estimate_lines: 270
---

# A test runs append_event and the Go appender over every event fixture and the committed sample, and compares the lines

Needs events-append-go. internal/events/bash_compare_test.go runs bash's append_event and the Go Appender over the same cases, each side into its own temp project. The bash side sources bin/lib/agents.sh with PROJECT_DIR set, and takes plugin_version cut from bin/swarm.sh, as tests/events_test.sh:298 and :360 do. The test reads both files with os.ReadFile, so go test's cache keys on them. bash's date is a stub, first on PATH, that prints one fixed instant (tests/diff_fixtures_go_paths.sh:13 pins one), and the Go gets the same instant as its now. HERDR_PANE_ID and the plugin root (a temp one) are the same on both sides. SWARM_FORBID_PROJECT is unset: the refusal is events-append-go's own Go test. The test compares events.tsv's bytes, stderr and each call's exit status, an Append error counting as 1. Cases come from internal/events/testdata/. They are: every direct append_event call in tests/events_test.sh (ev at :298, evv at :360), each with a comment naming its check; the 400 rows of tests/fixtures/events/v0.29.1-sample.tsv, read from that file, each appended with its command, target and outcome and k=v, as tests/events_tail_agents_test.sh:151-158 does; an outcome holding ' ~~ ' once and twice, and one ending in ' ~~ '; one ending in ' ~~'; tabs, LF and CR in each column; target, outcome and pane each empty or unset; fields that are empty, hold a space, have an upper-case key or hold a tab; no plugin.json; a plugin.json that plugin_version refuses; a version holding a space; versions ending in one LF, ending in two, holding one inside, and ending in a CR; plugin.json changed between two appends in one process; a project with no .swarm; and two writes that fail, .swarm a regular file and events.tsv a folder, where both sides fail and leave the file and the folder as they were. The test reaches inside the bash, so it adds its docs/port/tests.tsv row at its sorted place: `internal/events/bash_compare_test.go<TAB>lib,text<TAB>rewrite-from-outside<TAB>retired-with: bash-retired<TAB>bash-retired`. bash-retired deletes this test. port: true.

**Done when:**
- go test ./internal/events/ passes, and go test -v prints how many cases it compared: the case files in internal/events/testdata/ plus the sample's 400 rows.
- Mutation, on a copy without .git: make the Go keep tabs in the target and the comparison goes red; make the copy's agents.sh keep a trailing ' ~~' and it goes red; make the Go keep a version's trailing LF and the LF case goes red; make the Go Append drop its write error and the .swarm-is-a-file case goes red.
- `make test TESTS=tests/port_tests_list_test.sh JOBS=1 TEST_RUNS_LOG=` passes with the new row.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

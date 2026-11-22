---
kind: code
status: later
epic: board-store
depends_on: []
touches: [internal/plugin/plugin.go (new), internal/plugin/plugin_test.go (new), internal/plugin/bash_compare_test.go (new), internal/plugin/testdata/ (new), docs/port/tests.tsv:header, docs/port/tests.tsv:internal/plugin row]
estimate_lines: 250
---

# plugin_version's scan of plugin.json is Go, compared with the bash on every case

Needs no other story. A new rules package internal/plugin: Version(b []byte) (string, bool), bin/swarm.sh:131-202's plugin_version rule for rule. The input stops at its first NUL (read -d ''). Leading space, tab, LF and CR are skipped and a top-level object is required. A string runs to its closing quote with JSON's escapes; a \u escape is kept only for 1-127, otherwise the value no longer counts. A key is compared to version only at depth 1, and the last top-level version wins. An object, array or bare scalar as that value spoils it. Brackets must pair, and only whitespace may follow the closing brace. Write a scanner, not encoding/json: the bash takes text json.load refuses (no commas, bare words), and the Go must match the bash. The ^[^[:space:]]+$ filter and the trailing-LF strip belong to append_event (events-append-go). internal/plugin/bash_compare_test.go runs bash's plugin_version and Version over every case and compares stdout bytes and exit status; the Go side prints the value and a newline, as the bash does. The bash runs in one process, its text cut from bin/swarm.sh as tests/config_test.sh:437-442 cuts it; the test reads bin/swarm.sh with os.ReadFile, so go test's cache keys on it (a child process's reads are not tracked). The cases are every JSON that tests/config_test.sh:445-461 feeds, plus: a version in an array; true, null and a number as values; \u escapes of A, of é and of NUL; a NUL byte mid-file; a missing comma; a UTF-8 BOM; trailing junk; whitespace after the close; an empty object; a top-level array; and versions holding an escaped LF at the end, two at the end, one inside, and a CR at the end. Fixtures go in internal/plugin/testdata/, outside tests/, so the patch gate needs no touches line per file (contradictions: comparison location). The comparison reaches inside bin/swarm.sh, so it adds its docs/port/tests.tsv row at its sorted place (AGENTS.md; docs/port/README.md:17): `internal/plugin/bash_compare_test.go<TAB>text<TAB>rewrite-from-outside<TAB>retired-with: bash-retired<TAB>bash-retired`. It also widens the header's first line (docs/port/tests.tsv:1), which says the list holds only tests under tests/, to name the Go tests that run the bash beside the Go. bash-retired deletes the comparison. port: true.

**Done when:**
- go test ./internal/plugin/ passes, and go test -v prints how many cases it compared, equal to the files in internal/plugin/testdata/.
- Every JSON that tests/config_test.sh:445-461 feeds plugin_version is a case, its comment naming the check.
- Mutation, on a copy without .git: make the Go take a nested object's version and the comparison goes red; make the copy's bin/swarm.sh plugin_version keep the first of two top-level versions and it goes red too.
- `make test TESTS=tests/port_tests_list_test.sh JOBS=1 TEST_RUNS_LOG=` passes with the new row.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

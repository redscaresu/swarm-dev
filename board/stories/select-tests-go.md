---
kind: code
status: ready
epic: go-module
depends_on: []
touches: [scripts/select_tests.py:check_map Go paths, scripts/test-map.tsv:Go row, scripts/test-map.tsv:header check-map sentence, scripts/select-tests.sh:header --check-map comment, tests/select_tests_test.sh:--check-map Go cases, tests/select_tests_test.sh:header comment]
estimate_lines: 50
easy: true
---

# select-tests maps a changed Go file to its tests, and --check-map fails a tracked Go file with no row

Needs no other story. It works whether go-module-build merges before it or after, since the fixture repo carries its own paths.
- check_map (scripts/select_tests.py:697-698) only looks under MAPPED_DIRS (:45: bin/ scripts/ commands/ hooks/ docs/), so it never names a Go file. Make it also name any tracked path that ends in .go, and go.mod and go.sum, wherever they sit. The class is Go files, not one directory (rules.md).
- Add a row to scripts/test-map.tsv: `go.mod go.sum cmd/** internal/**<TAB>tests/doc_check_test.sh`. A renamed Go path can break a doc that names it (doc-check-go). Do not use `named`: no test names main.go, so it would select every test. select-tests --run runs only tests/*_test.sh; CI's go-checks job runs the Go tests.
- Update the header sentence (test-map.tsv:13-14) and select-tests.sh's --check-map comment (:8-9) to name the Go paths.
- tests/select_tests_test.sh, --check-map case (:376-387): with a map that has no Go row, add cmd/swarm/main.go, internal/x/y.go, go.mod and tools/z.go to the fixture paths it must name. Add a fixture-repo case where a branch that changes only cmd/swarm/main.go selects tests/doc_check_test.sh and not every test. The real-repo ls-files case must keep passing. Update the header comment (:18-20).

**Done when:**
- On a map with no Go row, --check-map names cmd/swarm/main.go, internal/x/y.go, go.mod and tools/z.go and exits 1. With the real map, a fixture branch that changes only cmd/swarm/main.go selects tests/doc_check_test.sh and nothing else. `git ls-files | scripts/select-tests.sh --check-map` on the real repo prints nothing and exits 0. On a worktree copy, dropping the Go clause from check_map turns the first case red, and deleting the Go row turns the second red.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: board-store
depends_on: [config-go]
needs: config-go: internal/config/keys.go with one `{name: "<key>", ...},` line per key
touches: [tests/doc_check_test.sh:doc_check settings read]
estimate_lines: 80
easy: true
---

# doc_check reads the setting names from the Go config list as well as CONFIG_KEYS

Needs config-go. This is the settings half of the go_check at docs/port/tests.tsv:45. doc_check's Python (tests/doc_check_test.sh:36-45) also reads the setting names from internal/config/keys.go, with a line regex for its `{name: "<key>", ...},` form, and uses the union with CONFIG_KEYS. When keys.go gives none it exits `FAIL doc_check: found no settings in <path to keys.go>`, as it already does for CONFIG_KEYS. doc_check takes the repo it reads as an argument, so two new checks run it on a copy of the files it reads (bin/swarm.sh, bin/lib/board.sh, internal/config/keys.go) with a docs root of their own. The first empties keys.go's key lines and expects that FAIL line. The second adds a key line that only keys.go has, and a doc naming `swarm.sh config <that key>` and `swarm.sh config nosuchkey`: doc_check must report the unknown key and nothing for the Go-only one. Today every Go key is also in CONFIG_KEYS, so only the second check proves the union is used. The command half is port-frame's. The CONFIG_KEYS read stays until bash-retired. port: true; touches lists the one tests/ file it changes.

**Done when:**
- tests/doc_check_test.sh passes; the first new check sees the FAIL line naming internal/config/keys.go, and the second sees `config key nosuchkey` and no line for the Go-only key.
- Mutation, on a copy without .git, under `make test TESTS=tests/doc_check_test.sh JOBS=1 TEST_RUNS_LOG=`: drop the fail-on-none for keys.go and the first check goes red; read only CONFIG_KEYS, dropping the union, and the second goes red.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: board-store
depends_on: []
touches: [tests/fixtures/events/redact.py:SOURCE_DIRS, tests/fixtures/events/redact.py:vocabulary, tests/events_fixture_test.sh:Go-word checks, scripts/test-map.tsv:go.mod row]
estimate_lines: 70
easy: true
---

# redact.py takes its allowed words from the Go source too, and never from Go tests or testdata

Needs no other story. This is the go_check at docs/port/tests.tsv:57. tests/fixtures/events/redact.py's SOURCE_DIRS (:28) gains cmd and internal, so a word that only Go code uses stays allowed in the fixture; its docstring (:11) says so. Under cmd and internal, vocabulary() (:67-77) takes only .go files whose names do not end in _test.go, outside any testdata/ folder: today it takes every file under a source dir, so a test's or a fixture's words would become allowed words and loosen the allowlist. tests/events_fixture_test.sh gains two checks. The first finds, at run time, a word token in a non-test .go file under cmd/ or internal/ and in no file under bin/, hooks/ or scripts/; redact.py --check must pass a file holding it. The second finds a word token that is only in a _test.go or testdata/ file under cmd/ or internal/, and in no file vocabulary() reads; redact.py --check must refuse a file holding it. Each fails, saying why, when it finds no such word. Every existing check keeps passing: the committed sample and the synthetic log's stand-ins. scripts/test-map.tsv:61's row (go.mod go.sum cmd/** internal/**) gains tests/events_fixture_test.sh, since redact.py now reads those trees through a directory walk, as that row's floor tests do. port: true; touches lists both tests/ files, as the patch gate needs (bin/lib/port_touches.py).

**Done when:**
- tests/events_fixture_test.sh passes; the first new check's line names the Go-only word it used, and the second's the test-only word.
- On a copy without .git, under `make test TESTS=tests/events_fixture_test.sh JOBS=1 TEST_RUNS_LOG=`: with cmd and internal taken back out of SOURCE_DIRS, the first check's FAIL line shows; with the _test.go and testdata/ filter removed, the second's shows.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

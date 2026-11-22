---
kind: code
status: later
epic: board-store
depends_on: [config-go]
needs: config-go: Parse, Defaults, and the key and removed-key lists in CONFIG_KEYS' and REMOVED_KEYS' order
touches: [internal/config/bash_compare_test.go (new), internal/config/testdata/ (new), docs/port/tests.tsv:internal/config row]
estimate_lines: 300
---

# A test runs load_config and the Go config parse over every config fixture, the bash tests' malformed ones included, and compares the bytes

Needs config-go. internal/config/bash_compare_test.go runs bash's load_config in one bash process, with the bash found on PATH (3.2 on macOS). It cuts bin/swarm.sh's settings block and load_config from the file, from `CFG_board_dir=docs` to load_config's closing brace, and adds die() as bin/swarm.sh:71-80 has it. Never source the whole of bin/swarm.sh: its top level looks for a project. The test reads bin/swarm.sh with os.ReadFile, so go test's cache keys on it. It also reads CONFIG_KEYS (:336) and REMOVED_KEYS (:339) from that text and fails unless the Go lists equal them, in order. It runs under set -euo pipefail, with HOME set, and CONFIG_FILE naming each fixture in turn. Each case runs in a subshell, so a die ends only that case. Each case prints its exit status and stderr and, when it loads, CFG_<key>=<value> and SRC_<key>=<source> for each key in CONFIG_KEYS' order. The Go side prints Parse's result the same way: the warnings, then `swarm: ` and the error. The two are compared byte for byte. Fixtures sit in internal/config/testdata/, one file per case, outside tests/, so the patch gate needs no touches line per file. They are: every config text that tests/config_test.sh and tests/removed_test.sh write before a load; and every config text any other tests/*_test.sh writes that load_config refuses or warns on. The builder finds those by grepping tests/ for the fixed words of each of load_config's 24 die and warning sites (bin/swarm.sh:347-426); env_allowlist_test.sh:381's bad agent_env name and merge_protected_setting_test.sh:92's merge_protected = maybe are among them. Each fixture's comment names its test file:line, or the site it reaches. Then: every key set at once; a key set twice; an empty file; only comments and blank lines; CRLF; no final newline; a # inside a value; ~ and ~/ in board_dir and repos_dir; a non-ASCII key; tabs around =; the two top_rung_rounds wrap cases. Each of the 24 sites is reached by one fixture at least. The no-file case compares Defaults() with bash's defaults. The escalate_ladder model check and agent_env's reserved names are not in load_config, so they are out of scope (contradictions). The test reaches inside bin/swarm.sh, so it adds its docs/port/tests.tsv row at its sorted place: `internal/config/bash_compare_test.go<TAB>text<TAB>rewrite-from-outside<TAB>retired-with: bash-retired<TAB>bash-retired`. bash-retired deletes this test with the bash. port: true.

**Done when:**
- go test ./internal/config/ passes. go test -v lists each fixture with the first line it printed, and their count equals the files in internal/config/testdata/.
- Each of load_config's 24 die and warning sites is reached by a fixture whose comment names it, and every tests/*_test.sh check of a load_config message has a fixture whose comment names that file:line, env_allowlist_test.sh:381 and merge_protected_setting_test.sh:92 among them.
- Mutation, on a copy without .git: change one word of the Go unknown-key message and the comparison goes red; make the copy's bin/swarm.sh merge arm accept auto and it goes red too; swap two keys in the Go list and the list check goes red.
- `make test TESTS=tests/port_tests_list_test.sh JOBS=1 TEST_RUNS_LOG=` passes with the new row.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

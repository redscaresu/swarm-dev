---
kind: code
status: later
epic: board-store
depends_on: [frontmatter-go]
needs: frontmatter-go: FM, GetFM, GetFMOrGone with ErrGone and GetFMText, each with the exact bytes printed, the printed flag and the error, and the Go SET_FM_KEYS list
touches: [internal/frontmatter/bash_compare_test.go (new), internal/frontmatter/testdata/ (new), docs/port/tests.tsv:internal/frontmatter row]
estimate_lines: 300
---

# A test runs fm, get_fm and get_fm_or_gone, plain and from a report's snapshot, and the Go over every board file and template and compares the bytes

Needs frontmatter-go. internal/frontmatter/bash_compare_test.go builds temp projects. Its corpus is every regular file under the checkout's board/ and templates/, dotfiles and .base files included, found at run time with no name filter and copied to its relative path: board/ into one board, and templates/ into another whose BOARD is its docs/, so the templates' stories/ and epics/ READMEs sit where the state rule looks. Fixture items and state files come from internal/frontmatter/testdata/. The test sources bin/lib/board.sh in one bash process, with the bash found on PATH. It runs under set -euo pipefail, as swarm.sh does: without pipefail, fm's || chain never reaches item_gone. PROJECT_DIR, BOARD and BOARD_STATE_DIR are set, and die() is as bin/swarm.sh:71-80 has it. The test reads board.sh with os.ReadFile, so go test's cache keys on it, and fails unless the Go SET_FM_KEYS equals :3175's. For every (file, key) pair, each key on a ^[a-z_]+: line anywhere in the file, each SET_FM_KEYS key and one key no file has, it runs fm, get_fm, get_fm_or_gone and `get_fm - <key> < <file>`, and records stdout bytes, exit status (get_fm_or_gone's 3 for a gone item) and stderr. The Go side runs FM, GetFM, GetFMOrGone (ErrGone as 3) and GetFMText through store.Files. Every pair runs twice: plain, then after board_snapshot <mark> (bin/lib/board.sh:36), so the snapshot's answers are compared too. The snapshot pass adds an item whose name holds a space, which board_snapshot leaves out (a miss), and one invalidation: the harness rewrites one item's state file, calls board_snap_written, and reads it again, where the Go reads the rewritten file. Stdout and exit status are compared byte for byte, and so is stderr for the state-file die. For an item that cannot be read, the test checks only that both sides fail with something on stderr: sed's and awk's own words and codes differ between GNU and BSD (contradictions). The fixtures, each a file: a state value over the file; an empty state value; a stale @base and a matching one; a state file that cannot be read; a state path that is a folder; a key outside SET_FM_KEYS with a state line; an hld item with a state file; a gone item; a dangling symlink item; an item that cannot be read (skipped as root); no front matter; --- not on line 1; a key in the body before the front matter; CRLF; a last line with no newline; `key:` with no space; `key:   x`; `key:` then a tab then x. Where bash's plain and snapshot passes disagree, that is a bash bug: the builder stops and tells the lead, and the Go follows the plain pass. The test reaches inside the bash, so it adds its docs/port/tests.tsv row at its sorted place: `internal/frontmatter/bash_compare_test.go<TAB>lib,text<TAB>rewrite-from-outside<TAB>retired-with: bash-retired<TAB>bash-retired`. bash-retired deletes this test. port: true.

**Done when:**
- go test ./internal/frontmatter/ passes. go test -v prints the manifest of compared files and, per pass, the number of (file, key) pairs.
- The test fails unless the manifest holds a file not named *.md from each of board/ and templates/: narrowing the discovery to *.md, on a copy without .git, makes it red.
- Mutation, on a copy without .git: make the Go FM strip a tab after the colon and the comparison goes red; make the copy's board.sh state_read ignore @base and it goes red; make GetFMOrGone succeed for a gone item and it goes red; make the copy's board_snap_read answer fm with get_fm's value and the snapshot pass goes red.
- `make test TESTS=tests/port_tests_list_test.sh JOBS=1 TEST_RUNS_LOG=` passes with the new row.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

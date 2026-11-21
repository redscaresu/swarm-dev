---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [cmd/swarm/main.go:run, cmd/swarm/frame.go (new), cmd/swarm/main_test.go, cmd/swarm/frame_test.go (new)]
estimate_lines: 270
---

# The Go binary dispatches by name and reads the frame bash hands it, with a fixture entry

Needs no other story. cmd/swarm/main.go:run today ignores its arguments and prints 'no command is ported yet' (cmd/swarm/main.go:20-27). Give it a table of entries by dispatch name. A name not in the table prints one line naming it and returns 2. The frame stays bash (P11): bash resolves the project, board and settings, then hands them over in SWARMDEV_ variables set only for the binary's run. Pin the names here for marker-dispatch: SWARMDEV_HOME, SWARMDEV_PROJECT, SWARMDEV_BOARD, SWARMDEV_DIE_FILE, SWARMDEV_FIELDS_FILE, and SWARMDEV_CFG_<key> and SWARMDEV_SRC_<key> for each setting. The Go reads every SWARMDEV_CFG_ name it finds and keeps no copy of CONFIG_KEYS (board-store owns the Go config). An entry that needs the frame refuses to run without SWARMDEV_PROJECT, in one line saying to run it through bin/swarm.sh; hooks will later call entries that need no frame. A failure writes its first line, without 'swarm: ', as the die file's only line, as die() does (bin/swarm.sh:72-80). The line goes on stderr with the prefix, and the run returns the code. Add a fixture entry, wrapper-fixture, for the wrapper's tests. It prints its args, stdin, and each frame value with its source, one per line in a fixed order. Told to, it fails with a given line and code, or writes event fields to the fields file. A Go test pins that the table and the marker files under bin/ported/ name the same entries, fixtures aside; a missing bin/ported/ counts as empty. The real tree gets no marker in this epic.

**Done when:**
- go test: wrapper-fixture run with the handoff set prints the project, board, home, its args, its stdin and every SWARMDEV_CFG_ key with its value and source; with SWARMDEV_PROJECT unset it prints the one line and returns 2.
- go test: the fixture told to fail with line L and code 3 writes exactly L as the die file's only line, prints 'swarm: L' on stderr and returns 3; with SWARMDEV_DIE_FILE empty it writes no file.
- go test: a name not in the table prints one line naming it and returns 2.
- go test: an entry added to a test table with no marker fails the table-and-markers check, and so does a marker with no entry.
- gofmt -l . prints nothing, and go vet and the go-checks job (go.yml) pass on the PR's head.
- tests/port_swarm_names_test.sh passes: the Go reads only SWARMDEV_ names, which its SWARM_[A-Z0-9_]+ scan does not match.
- Mutation: drop the die-file write and the second check goes red.
- scripts/select-tests.sh --run passes

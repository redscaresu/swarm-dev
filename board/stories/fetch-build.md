---
kind: code
status: ready
epic: binary-fetch
depends_on: []
touches: [bin/lib/binary.sh:binary_build (new, above binary_path), bin/lib/binary.sh:binary_path (its build moved into binary_build), tests/binary_source_test.sh, docs/port/tests.tsv:tests/binary_source_test.sh row]
estimate_lines: 190
---

# binary_build builds the binary from the source beside it, atomically, and names both Go versions when the local Go is older

Needs no other story.
Where: bin/lib/binary.sh. binary_build is a new function right above binary_path's comment (:60). binary_path (:71-92) hands its build to it.
binary_build <root>: `go build ./cmd/swarm` from <root> into <root>/swarm<BINARY_BUILD_TMP><pid>, then mv -f onto <root>/swarm, as binary_path does today (:84-90), on a root with or without .git. Each stop is one `binary: ` line, return 1, and leaves any <root>/swarm as it was:
- no go.mod or no cmd/swarm under <root> (a 0.31.x install has no source);
- no go on PATH: name go.mod's Go version (its `go` line, go.mod:3, read with builtins) and say to install it;
- a failed build: when `go env GOVERSION` is older than go.mod's version, by a numeric compare of the dotted fields and never by Go's error text, one line naming both versions and saying to install go.mod's or reconnect so Go can fetch it, then Go's error. Otherwise, or with a GOVERSION it cannot parse (a devel build), today's line and Go's error.
binary_path keeps its checkout behaviour and lines: tests/binary_build_test.sh passes unchanged. Here only binary_path calls binary_build; fetch-fallback calls it for an installed copy.
A KILL mid-build leaves the swarm.build-<pid> file, which no call runs; .gitignore covers it in a checkout.
Tests: new tests/binary_source_test.sh sources binary.sh and adds its docs/port/tests.tsv row. Use a no-.git copy whose cmd/swarm/main.go prints a word (as tests/binary_build_test.sh:42-64), real go behind a logging stub, and go stubs for the version cases. For the KILL, a go stub writes half a file to its -o path and then blocks; use in_new_group and stop_group (tests/test_helpers.sh).

**Done when:**
- On a no-.git copy, binary_build returns 0, <copy>/swarm prints the word, and no swarm.build-* file is left.
- No go on PATH: return 1 with one line naming go.mod's 1.27.1, and no <copy>/swarm. A copy with no cmd/swarm, and one with no go.mod: return 1 with one line each, and the go stub logs no build.
- A go stub whose GOVERSION is go1.0.0 and whose build fails: one line naming go1.0.0, 1.27.1 and what to do, then the stub's error. One whose GOVERSION is go1.99.0 and whose build fails: today's line and the stub's error, not the older-Go line.
- With a good <copy>/swarm present, a failed build leaves it cmp-equal to before. So does the half-writing go stub killed with KILL to its process group.
- tests/binary_build_test.sh passes unchanged.
- Mutations on a copy, FAIL lines quoted, each turning a named case red: the version compare removed (the go1.0.0 case); the compare inverted (the go1.99.0 case); the build written straight onto <copy>/swarm instead of through the temp file and mv (the KILL case).
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

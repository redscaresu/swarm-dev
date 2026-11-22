---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [go-entries-per-file]
needs: go-entries-per-file (helpers-shared): register from an entry's own file (cmd/swarm/frame.go) and docs/port/README.md § Two forms.
touches: [cmd/swarm/cigate.go, bin/ported/_ci-gate, internal/merge/cigate.go, internal/merge/cigate_test.go, tests/ci_gate_cases_test.sh, tests/ci_gate_cases/base.cases, docs/port/tests.tsv:tests/ci_gate_cases_test.sh row, scripts/test-map.tsv:internal/merge row]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the binary's _ci-gate entry, and a test that runs each mode on Python and Go over the same recorded gh answers

Needs go-entries-per-file: an entry registers from its own file.
The frame of the port, with no mode yet.
- `_ci-gate` registers from cmd/swarm/cigate.go with needsFrame false, since CI's gate runs it with no project (scripts/board-only.sh:56-61), and its marker bin/ported/_ci-gate (cmd/swarm/frame_test.go:160-166 fails an entry without one). Nothing calls it until the switch.
- internal/merge/cigate.go: a registry each later story's own file adds modes to; a name with no mode goes to main's arm (:1066); an error prints `error <msg>` on stdout and exits 3 (:1071-1073). A mode gets the CodeHost, the Store, the environment, the clock and a sleep. ci_gate.py reads time.time() and never SWARM_DASH_NOW, so the Go reads the real clock and sleeps unscaled. It writes only the paths its caller names, as ci_gate.py does; P5's forbid check is the frame's (bin/swarm.sh:201-211), which every bash caller passes first.
- tests/ci_gate_cases_test.sh: one case file per mode under tests/ci_gate_cases/. A case holds its arguments, environment, gh answers by exact argv, and wants: stdout, stderr, exit code and the gh calls in order. Every case runs on python3 bin/lib/ci_gate.py, and a file marked go also runs on `$SWARMDEV_BIN _ci-gate`, with gh a stub that answers the recorded argv and fails any other. An answer holding a time writes it relative to the run's clock. Only a line that embeds Python's exception text (contradiction 6) may hold a want per side, marked with the ci_gate.py line it comes from.
- A seed, base.cases, on the Python side only; ci-gate-go-rules marks it go.
- Rows: docs/port/tests.tsv (py reach), and scripts/test-map.tsv running it for internal/merge/**, cmd/swarm/cigate.go and tests/ci_gate_cases/*, before the go.mod cmd/** internal/** row (test-map.tsv:61) and keeping that row's tests.
Python's own texts on input no swarm.sh caller gives (an IndexError on a missing argument) have no Go twin; the PR lists them.

**Done when:**
- (1) `swarm _ci-gate base o/r <sha>` with SWARM_PROJECT unset reaches the registry (no base mode yet: `error ...`, exit 3), where an entry with needsFrame stops with exit 2. (2) Go tests: a mode's error prints `error <msg>` and exits 3; an unknown name runs the mode registered as main; with none it prints `error ...` and exits 3. (3) tests/ci_gate_cases_test.sh passes on the seed. On a worktree copy without .git: ci_gate.py's base arm changed alone makes it red naming python, the file and the case; the seed marked go makes it red naming go; a stderr line dropped from a want makes it red. The PR quotes the FAIL lines. (4) TestTableMatchesMarkers passes, and fails with bin/ported/_ci-gate removed. (5) port_tests_list_test.sh passes, and fails with the new row removed. (6) On a branch that changes only internal/merge/cigate.go, scripts/select-tests.sh --run runs tests/ci_gate_cases_test.sh. (7) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

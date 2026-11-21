---
kind: code
status: blocked
epic: binary-wrapper
depends_on: [go-frame-entry, marker-dispatch]
needs: go-frame-entry: cmd/swarm/frame.go's wrapper-fixture and handoff reader, which gain a second form; marker-dispatch: dispatch's marker route and tests/binary_dispatch_test.sh, which gains the two-forms cases
touches: [cmd/swarm/bridge.go (new), cmd/swarm/bridge_test.go (new), cmd/swarm/frame.go:fixture, tests/binary_dispatch_test.sh:two forms, docs/port/swarm-names.tsv:SWARM_PROJECT row, docs/port/swarm-names.tsv:SWARM_GH_VIA row]
estimate_lines: 240
---

# A ported command hands a form still in bash to a _ name, and bash calls a _ entry of the binary

Uses go-frame-entry's cmd/swarm/frame.go (the fixture and the handoff reader) and marker-dispatch's marker route and tests/binary_dispatch_test.sh. No marker routes by flag (epic constraint). When a command's first port leaves one form in bash, that form moves to a `_` name, and the Go runs it through swarm.sh (P9). Add that bridge to cmd/swarm. It runs `bash <SWARMDEV_HOME>/bin/swarm.sh _<name> <args>` with SWARM_PROJECT set to the frame's project, and it inherits SWARM_GH_VIA, so the nested call resolves the same project and logs its gh calls under the same via (bin/swarm.sh:224-227). stdin, stdout, stderr and the exit code pass through unchanged. No existing `_` arm uses every argument (_board-rel ignores them, bin/swarm.sh:713; _name reads the first, :707), so a Go test runs the bridge against a stub swarm.sh under a temp SWARMDEV_HOME that records them (codex). bridge.go names SWARM_PROJECT and SWARM_GH_VIA, so add it to both rows of docs/port/swarm-names.tsv (codex, critic). Give wrapper-fixture a second form that the bridge hands to an existing read-only `_` arm of dispatch (such as _name or _board-rel), so no bash arm is added for a test. Add a `_` Go fixture entry, _wrapper-fixture, for the reverse: bash calls it as `"${BASH}" "${SWARM_HOME}/bin/swarm.sh" _x`, as it calls _step-up today (bin/lib/lifecycle.sh:1328). The test's copy gives each fixture a marker; the real tree gets none.

**Done when:**
- tests/binary_dispatch_test.sh: the Go form gets exactly its args; the bash form, reached through the bridge, prints what the `_` arm prints for the same args and exits with its code.
- Each form's usage error reaches the caller: the Go form's line and exit 2, and the bash arm's message and exit code, unchanged.
- "${BASH}" <copy>/bin/swarm.sh _wrapper-fixture a 'b c' runs the binary with those two args. lead_rename does not run for it (bin/swarm.sh:626): a herdr stub logs no rename.
- go test: the bridge, run against a stub swarm.sh that records its arguments, stdin, cwd, SWARM_PROJECT and SWARM_GH_VIA, writes a line to stdout and one to stderr and exits 7: passes a, 'b c' and an empty argument in order, the stdin, both lines on their own streams, and exit 7.
- tests/port_swarm_names_test.sh passes with cmd/swarm/bridge.go on SWARM_PROJECT's and SWARM_GH_VIA's rows.
- Mutation: drop the last argument and the stub check goes red; drop SWARM_PROJECT and run from another cwd, and the bash-form check goes red.
- scripts/select-tests.sh --run passes

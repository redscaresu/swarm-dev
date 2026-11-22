---
kind: code
status: later
epic: board-store
depends_on: [store-file-reads, plugin-version-go]
needs: store-file-reads: AppendLine (makes .swarm, one write, returns its error), RealPath and ReadFile on iface.Store; plugin-version-go: plugin.Version, to read the version= value from plugin.json
touches: [internal/events/events.go (new), internal/events/events_test.go (new), docs/port/swarm-names.tsv:SWARM_FORBID_PROJECT row]
estimate_lines: 280
---

# append_event is Go, with the same five columns, field rules and version=, and it refuses SWARM_FORBID_PROJECT

Needs store-file-reads and plugin-version-go. A new rules package internal/events ports append_event (bin/lib/agents.sh:983-1000) and its constants: EVENTS_LOG (:956), EVENT_SEP (:964, exported as Sep) and EVENT_VERSION (:973). An Appender holds the store, PROJECT_DIR and the plugin root (the frame's SWARMDEV_HOME). At its first append it reads <root>/.claude-plugin/plugin.json once through plugin.Version; an empty root reads /.claude-plugin/plugin.json, as bash does. It strips every trailing LF from the value, as the $( ) at :987 does, then keeps it only when it matches ^[^[:space:]]+$ (:988): a version ending in LF loads, and one ending in CR or holding an LF inside does not. Append(now, command, target, outcome, fields...) takes the time from its caller; production callers pass clock.Real(), because bash's date -u reads no test clock. The outcome defaults to ok when unset or empty, and its tab, LF and CR become spaces. Then repeat until neither is left: every ' ~~ ' becomes a space, one trailing ' ~~' goes, and trailing spaces go. A field must match ^[a-z_]+=[^[:space:]]+$, with [:space:] as frame.go's fieldSpace. A field that fails is left out, with `append_event: left out <x cut at its first tab, LF or CR>: a field is key=value, the key [a-z_]+, the value not empty and with no whitespace` on stderr, and the line is still written. version= goes last. The columns are: the time as %Y-%m-%dT%H:%M:%SZ in UTC; the command; the target or -; HERDR_PANE_ID or -; the outcome, then ' ~~ ' and the tail when there is one. Every column's tab, LF and CR become spaces. One AppendLine to PROJECT_DIR/.swarm/events.tsv. Its error is returned, and nothing more goes on stderr, as bash's 2>/dev/null drops mkdir's and the redirect's words (:999); record_event's || true is the caller's. It takes no lock, as bash takes none, so P4's lock test has nothing to hold. Before writing it refuses as hooks/lead-stop.sh:72-79's forbidden() does: when SWARM_FORBID_PROJECT is set and its RealPath equals PROJECT_DIR's, it writes nothing, makes no folder and returns an error naming SWARM_FORBID_PROJECT. The worktree half of bin/swarm.sh:279-287 stays the frame's, which port-frame ports (contradictions: refusal). SWARM_FORBID_PROJECT is the one SWARM_ token a non-test file of the package names, so events.go joins its row (docs/port/swarm-names.tsv:41); a comment naming any other fails tests/port_swarm_names_test.sh. The reviewer reads append_event against the Go rule by rule (P6). port: true.

**Done when:**
- Go tests over a temp project write the exact line for each of: an outcome holding ' ~~ ' twice; an outcome ending in ' ~~'; a tab in the target; an empty target; an unset HERDR_PANE_ID; a bad field, with its exact stderr line; plugin.json changed between two appends of one Appender, where the first version stays; and plugin.json versions of 1.0 then an LF (version=1.0), 1.0 then a CR (no version=) and 1. then an LF then 0 (no version=).
- A Store whose AppendLine fails makes Append return that error, with nothing on stderr when every field is good.
- With SWARM_FORBID_PROJECT naming the project through a symlink, Append returns an error and no .swarm folder exists afterwards; with it naming another folder, the line is written.
- `make test TESTS=tests/port_swarm_names_test.sh JOBS=1 TEST_RUNS_LOG=` passes with events.go on the SWARM_FORBID_PROJECT row.
- Mutation, on a copy without .git: drop the refusal and the forbid test goes red; drop the trailing ' ~~' cut and its case goes red; drop the LF strip and the 1.0-then-LF case goes red; return nil where AppendLine failed and the failing-store test goes red.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass, the layer checks among them.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

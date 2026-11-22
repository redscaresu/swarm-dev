---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/iface/iface.go:CodeHost, internal/iface/iface.go:package comment, internal/adapter/gh/gh.go:Host, internal/adapter/gh/gh_test.go, internal/merge/gh.go, internal/merge/gh_test.go]
estimate_lines: 280
risk: high
---

# Go that nothing runs: the code host's one gh method, and ci_gate's gh, graphql and constants

Adds iface.CodeHost's first method, which helpers-shared's go-report-gh reuses (contradiction 3): run gh from PATH with these arguments, stdin closed, under a context. It returns stdout and stderr as bytes and how gh ended: its exit code, the signal that killed it, why it could not start, or cut short when the context ended, with gh killed then. A context with a deadline is report's bound (bin/lib/report.py:175-239). One with none is ci_gate.py's calls, which have no bound of their own (ci_gate.py:22-26). A cancelled one is queued's stop. internal/adapter/gh implements it (gh.go:10 asserts Host is a CodeHost).
In internal/merge: Err; gh (ci_gate.py:22-26), whose error names the call and gh's last stderr line, or 'exit <n>', a signal's death as Python's negative code; graphql (:235-246): ints, and bools as Python's isinstance(True, int) has them, as -F, the rest -f, and 'unreadable GraphQL answer: no repository'; and OK, READ_TRIES, UNLISTED, TRANSIENT, RUN_ID, COMPARE_FILES and the exit codes.
graphql's other error embeds Python's exception text: the Go prints the same prefix and its own reason (contradiction 6).
It rewrites iface.go's package comment so it states no count of methods; no other story edits it.

**Done when:**
- (1) Adapter tests with a stub gh on PATH: stdin is closed; stdout and stderr come back byte for byte, bad UTF-8 included; exit 3; a gh that kills itself with TERM; no gh on PATH; a sleeping gh past a context deadline is killed and the result says cut short; a cancelled context the same. (2) Go tests through a fake CodeHost: gh's error text for stderr with several lines, for none ('exit 3') and for a TERM death, each equal to ci_gate.py's gh on the same stub (the PR shows the python3 runs); graphql's argv for an int, a string and a bool; 'no repository'; an unreadable answer's prefix. (3) Each new test goes red on a worktree copy without .git where its rule is broken (stdin left open; the first stderr line taken for the last; ints sent as -f); the PR quotes the FAIL lines. (4) go test ./internal/layers/ passes. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

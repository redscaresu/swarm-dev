---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/pyvalues.go, internal/merge/pyvalues_test.go]
estimate_lines: 250
risk: high
---

# Go that nothing runs: JSON read as Python's json reads it, values printed as Python's %s and %r print them, and json.dumps' bytes

internal/merge cannot import helpers-shared's internal/pyfmt: a protected package imports only the four, iface and clock (internal/layers/protected_test.go:16-20). So merge keeps its own, pinned to python3 (contradiction 2).
- A decoder that keeps what ci_gate.py's isinstance checks and %s read: null, bool, int of any size apart from float, string, list, and object with its keys in order; NaN, Infinity and -Infinity as json.loads takes them; refusing what json.loads refuses.
- Str and Repr: a value as Python's %s and %r print it: None, True, 5, 5.0, 1e+16, 1e-05, nan, a string's repr with Python's quote choice and escapes, a list's and an object's repr.
- Dumps: the bytes json.dumps writes for strings, ints, null, and lists and objects of them: ', ' and ': ' separators, ensure_ascii's escapes with surrogate pairs, no HTML escaping. The poll cache's key, head's memo and main's wait records use it.

**Done when:**
- (1) A table test whose wants are python3's output on the same JSON (the PR shows the run): str and repr of null, true, 5, 5.0, 1e16, 1e-5, 0.1, -0.0, 2**70, NaN, a string holding ', ", both, a newline, the byte 0x01, an accented letter and an emoji, a nested list, and an object keeping key order. (2) Dumps of a pages argv holding & and ?, a non-ASCII argument, an emoji and a record with an int, null and a list equals python3's json.dumps bytes. (3) The decoder refuses a trailing comma and a bare word, and keeps 5 apart from 5.0. (4) Each goes red on a worktree copy without .git where its rule is broken (repr always single-quoting; HTML escaping on; 5.0 read as 5); the PR quotes the FAIL lines. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

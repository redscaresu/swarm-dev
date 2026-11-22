---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [ci-gate-go-gh, ci-gate-go-pyvalues]
needs: ci-gate-go-gh: gh, Err and the CodeHost method (internal/merge/gh.go). ci-gate-go-pyvalues: the decoder and Str (internal/merge/pyvalues.go).
touches: [internal/merge/reads.go, internal/merge/reads_test.go]
estimate_lines: 260
risk: high
---

# Go that nothing runs: docs, pages, judge and checks, the reads every ci_gate mode shares

Needs ci-gate-go-gh: gh and Err. Needs ci-gate-go-pyvalues: the decoder and Str.
Adds docs, pages (no poll cache yet: ci-gate-go-cache-lock adds it), judge and checks with its done parameter (ci_gate.py:28-96).
- docs skips what Python's str.isspace skips between documents, which is more than JSON's whitespace, and errs on an empty answer ('no answer for') and an unreadable one.
- pages' total_count is an int as isinstance has it: true counts, as 1; 5.0 does not.
- judge and checks print a field that is missing or not a string as Python's %s does.
- checks' done collects each run's completed_at and each status's updated_at, as read; age uses them.
- checks takes the required checks as a parameter (ci_gate.py:77); it does not call required().

**Done when:**
- (1) Table tests through a fake CodeHost that answers recorded argv and fails any other call: docs on two pages with a newline and the byte 0x1c between them, an unreadable page and an empty answer; pages on a short read ('<path>: read 2 of 3'), a non-object item, and total_count true and 5.0; checks green, red, pending, status-only with need_run false, a run with no name and a bool status, done's collected times, and a required check bound to an app with no run from that app. Each want is ci_gate.py's on the same answers; the PR shows the python3 runs. (2) Each new test goes red on a worktree copy without .git where its rule is broken (pages taking 5.0; done dropping statuses; docs skipping only JSON whitespace); the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

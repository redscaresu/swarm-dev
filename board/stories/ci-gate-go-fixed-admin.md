---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/fixed.go, internal/merge/fixed_test.go, tests/ci_gate_cases/fixed.cases, tests/ci_gate_cases/admin.cases]
estimate_lines: 270
risk: high
---

# Go that nothing runs: the fixed and admin modes

Needs parts' rules, and core's globs, reads, gh, pyvalues and entry.
Adds fixed, with FIXED_WALK (ci_gate.py:947-986), and admin (:144-155), and registers both (:1002-1006, :1034-1038). admin reads a compare's behind_by as Python's ['behind_by'] does: a missing key is an error whose text is Python's (contradiction 6). Adds fixed.cases and admin.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with fixed and admin marked go: fixed; why not; a walk back over board-only commits; the twentieth commit; admin's skipped rules, red and waiting checks, a strict base the head is behind, and a base name holding '/'. (2) Each case file goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

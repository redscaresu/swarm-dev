---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/behind.go, internal/merge/behind_test.go, tests/ci_gate_cases/behind.cases, tests/ci_gate_cases/merged.cases]
estimate_lines: 250
risk: high
---

# Go that nothing runs: the behind and merged modes

Needs core's gh, globs and entry.
Adds behind (with Unlisted) and merged (ci_gate.py:176-233), and registers both (:1039-1049). A transient failed read sleeps the <wait> bash passes and reads again, up to READ_TRIES, as the Python does. Their unreadable-compare errors embed Python's exception text (:197, :222; contradiction 6). Adds behind.cases and merged.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with behind and merged marked go: behind's count and its off-board files; a compare that lists 300 files (`error ...`, exit 4); a transient failure read again after the wait, and a 404 not read again; merged's ' and N more'. (2) Each case file goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

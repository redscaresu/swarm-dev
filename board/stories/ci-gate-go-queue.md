---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/queue.go, internal/merge/queue_test.go, tests/ci_gate_cases/queue.cases, tests/ci_gate_cases/pushed.cases]
estimate_lines: 170
risk: high
---

# Go that nothing runs: the queue and pushed modes

Needs core's gh and entry.
Adds has_queue and pushed (ci_gate.py:248-275) and registers queue and pushed (:1050-1054). A failed read sleeps the <wait> bash passes and reads again, as the Python does. Adds queue.cases and pushed.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with queue and pushed marked go: queue yes, no, and three failed reads; pushed's base head once it holds the commit, and a base that does not yet. (2) Each case file goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

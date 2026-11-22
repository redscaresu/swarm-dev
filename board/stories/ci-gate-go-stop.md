---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [ci-gate-go-signals]
needs: ci-gate-go-signals: the ignore span in the deps (internal/merge/cigate.go). Core: ci-gate-go-gh (graphql, Err), ci-gate-go-reads (checks), ci-gate-go-entry (the registry and the case runner).
touches: [internal/merge/stop.go, internal/merge/stop_test.go, tests/ci_gate_cases/stop.cases]
estimate_lines: 270
risk: high
---

# Go that nothing runs: turning a PR's auto-merge off and taking it out of the queue, and the stop mode

Needs ci-gate-go-signals: the ignore span. Needs core's gh, reads and entry.
Adds stop, Stopped, stop_pr, when, group_commit, removals and dequeued (ci_gate.py:277-364), and registers stop (:1055-1056). stop runs inside the ignore span (:325-343). Adds stop.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with stop marked go: auto-merge on and queued, auto-merge only, neither, and a failed read. (2) Go tests through fake hooks: stop runs inside the ignore span and finishes; dequeued's reasons from a merge group's red checks and from a removal. (3) Each new test goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: later
epic: helpers-ci-gate
depends_on: [ci-gate-go-main-poll, ci-gate-go-main-rerun]
needs: ci-gate-go-main-poll: the poll's verdict, ci_state and next_poll (internal/merge/mainpoll.go). ci-gate-go-main-rerun: the rerun type and red_line (internal/merge/rerun.go). Parts: ci-gate-go-records (the record lifecycle, covering), ci-gate-go-head-expected (expected), ci-gate-go-rules (required). Core: ci-gate-go-entry.
touches: [internal/merge/mainwait.go, internal/merge/mainwait_test.go, tests/ci_gate_cases/main.cases]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the main mode, main_ci's wait for CI on the base after a merge

Needs ci-gate-go-main-poll and ci-gate-go-main-rerun. Needs parts' records, head-expected and rules, and core's entry.
Adds main_wait's loop and main_ci (ci_gate.py:796-937): required read once, with its warning on stderr; expected when first needed, kept in the record; covering before each later read (CI_COVERED); missed reads; the timeout line; the sleep of the shorter of the interval and the time left. Registers main as the default arm (:1066-1070), with exits CI_OK, CI_RED, CI_TIMEOUT, CI_ERROR and CI_COVERED. Its gh calls keep Python's order, since the differential run compares them. merge_ci_budget_test.sh's simulated wait (:18-60) becomes a Go test on a fake clock; the switch deletes the Python one. Adds main.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with main marked go: ok; ok with a warning line and a flaky line; red with its note; timeout; covered (exit 4); an error after three failed reads; the required-checks warning on stderr. (2) A Go test on a fake clock with merge.sh's MERGE_POLL, MERGE_POLL_MAX and MERGE_CI_SECONDS: CI pending for the whole span ends in a timeout; it makes at most half the calls a fixed poll makes; each read is three calls; the gap grows to the cap; the read after a run starts comes a poll later. (3) Each new test goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

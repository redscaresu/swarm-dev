---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/head.go, internal/merge/head_test.go, tests/ci_gate_cases/head.cases]
estimate_lines: 250
risk: high
---

# Go that nothing runs: the head mode

Needs parts' head-expected, rules and cache-lock, and core's reads and entry.
Adds head_expected's newest pull_request run per workflow (ci_gate.py:684-695) and registers head (:992-1001). A red head is red whatever has run, so the expected workflows are read only when nothing is red; 'not waited on: <workflows>' is a second line; exit 1 is red, 2 waiting. head is the mode most callers use: wait-pr, the review agent, the lead's heads pass and CI's gate. Adds head.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with head marked go: green, red, pending, a red head with expected workflows (no workflow read among its gh calls), a pull_request workflow with no run on the head, an older run a newer one replaced, an inactive workflow, an unread workflow ('not waited on:'), the memo form, the bare `head <repo> <sha>` form board-only.sh uses, and a head under SWARM_POLL_CACHE as wait-pr runs it (merge.sh:2606), whose second run takes the kept reads. (2) Each case file goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

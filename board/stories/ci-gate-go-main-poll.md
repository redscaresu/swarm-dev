---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/mainpoll.go, internal/merge/mainpoll_test.go]
estimate_lines: 270
risk: high
---

# Go that nothing runs: one poll's verdict in main's wait for CI after a merge

Needs parts' rules and core's reads and gh.
What main_wait decides from one read (ci_gate.py:865-895, :921-930), as a function of the poll's state and the time, which ci-gate-go-main's loop calls: runs a rerun made pending ('rerun requested'); the required checks' runs split from the rest; the absent rule (once every expected push workflow has finished, or grace is over with none expected, a required check with no run means every check counts); the red, waiting and warning lines; 'held until every required check has a run'; '(no run on <sha>)'; and the ok line with its warnings and flaky lines. Also ci_state and next_poll (:729-740).

**Done when:**
- (1) Go tests, each want what python3 ci_gate.py main prints on answers that end it in one read (the PR shows the runs): every required check green with another red (ok and a warning); a required check red; a required check with no run while push workflows run (held), and once they finish (every check counts); none required with grace not over (waiting); a flaky line. (2) next_poll doubles to the cap and drops back to poll on a change; ci_state sorts as Python's does. (3) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

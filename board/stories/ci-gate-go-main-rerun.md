---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/rerun.go, internal/merge/rerun_test.go]
estimate_lines: 230
risk: high
---

# Go that nothing runs: main's rerun of a red run's failed jobs, and its red line

Needs core's gh.
Adds main_wait's rerun (ci_gate.py:896-920) and red_line (:939-945), as a type main's loop drives: each run reruns once, with `gh run rerun <id> --failed --repo <repo>`, only once its runs have finished; a TRANSIENT gh error is a missed poll and READ_TRIES in a row an error; a refusal is red with its note; a rerun that starts gives a fresh wait of secs; the rerun's old red checks read 'rerun requested' until they change.

**Done when:**
- (1) Go tests through a fake CodeHost, each want what python3 ci_gate.py main prints on the same answers (the PR shows the runs): one rerun per run; a run still going is held ('finishing before its rerun'); a transient failure, and three in a row ('(3 reruns in a row failed)'); a refusal's red line with its note; red_line's three notes. (2) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (3) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

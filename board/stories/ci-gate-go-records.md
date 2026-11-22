---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/records.go, internal/merge/records_test.go]
estimate_lines: 260
risk: high
---

# Go that nothing runs: main's wait records, covering, and their lifecycle

Needs core's cache-store, gh and pyvalues.
Adds alive, wait_record and covering (ci_gate.py:742-794), and main_ci's record lifecycle (:796-818): the record written before the wait, the warning on stderr when it cannot be, and the record, its temp and an emptied folder removed after. A record keeps Python's name (<sha>-<pid>.json), its temp (<path>.tmp) and its JSON, so a Python wait and a Go wait on one machine read each other's (HLD:447-449). The warning embeds OSError's text (:806; contradiction 6).

**Done when:**
- (1) Go tests: a record is written through <path>.tmp and renamed; covering ends a wait for a newer live merge's record that covers it, and skips a dead pid's, one on another base, and one whose want lacks a workflow; it reads a commit's compare once, and a failed compare again on the next poll. (2) ci_gate.py's covering reads a record the Go wrote, and the Go reads one ci_gate.py wrote; the PR shows both. (3) After the wait the record, its temp and the emptied folder are gone; a folder holding another wait's record stays. (4) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

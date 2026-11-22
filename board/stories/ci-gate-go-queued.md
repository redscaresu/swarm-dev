---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/queued.go, internal/merge/queued_test.go, tests/ci_gate_cases/queued.cases]
estimate_lines: 300
risk: high
---

# Go that nothing runs: the queued mode and the signals a merge sends it

Needs parts' stop and signals, and core's gh and entry.
Adds queued (ci_gate.py:366-443) and registers it (:1057-1060): merged (0), dequeued (1), timeout (2), error (3), never read as queued (4), an open PR at another head (5), a merge at another head (6), and a TERM, HUP or INT (7). On 2, 3, 4, 5 and 7 it turns auto-merge off and takes the PR out of the queue first. A signal during a gh call cuts it short, as Python's Stopped interrupts one.
It carries merge_queue_test.sh's go_check (docs/port/tests.tsv:100): a Go test of the signals, in place of the case that runs a patched copy of ci_gate.py (merge_queue_test.sh:256-276), which the switch deletes. Adds queued.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with queued marked go, one case for each exit from 0 to 6. (2) Go tests through the hooks: a TERM the moment queued starts catching is a stop (7) with the PR stopped, never an escape; a TERM during a gh call cuts it short and stops; a TERM, HUP or INT during the stop is ignored; the second line says what was undone. (3) A process test: `swarm _ci-gate queued` sent TERM while it waits exits 7, and the gh stub's log shows auto-merge turned off. (4) Each new test goes red on a worktree copy without .git where the Go alone, or ci_gate.py alone, is broken; the PR quotes the FAIL lines. (5) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [bin/lib/board.sh:merged_review, bin/lib/lifecycle.sh:close_when_idle (new), tests/reconcile_pull_test.sh:merged_review cases, docs/reference-merging.md:Merging (reconcile closes review-<slug>)]
estimate_lines: 180
easy: false
---

# A review pane closes itself after its own merge

#690. When `swarm.sh merge` runs from review-<slug>'s own pane, merged_review (bin/lib/board.sh:2655-2693) retires it to review-<slug>-done and leaves it for tidy. Closing it inline would kill the running merge, so add close_when_idle <name> <pane> to lifecycle.sh: a detached waiter in its own session (as lifecycle.sh:3846 detaches) that polls the agent's state until its turn ends, then closes the pane through shut_agent/close_pane; past a limit (a constant under 30 minutes) it leaves a working pane open and records a line saying so. merged_review's own-pane branch calls it after retire_agent. A review pane in another pane stays as today: idle closed, working left with its line.

**Done when:**
- tests/reconcile_pull_test.sh: a merge run from review-a's own pane (fake herdr) gets `pane close <its pane>` only after the merge command has exited and the agent reads idle; it goes red with the call removed from merged_review.
- The same test with the agent still working past the limit: no pane close, and a line names review-a as left open while working.
- The test waits for or stops the detached waiter, so it never outlives the test.
- The existing case at reconcile_pull_test.sh:534 (review-a working in another pane is left open, with its line) still passes.
- docs/reference-merging.md § Merging (lines 28-33) no longer says tidy --yes closes the retired pane later.

---
kind: lead
status: ready
epic: test-speed
after: test-speed
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: no test process is left with PPID 1 after the first real codex review under v0.28.0

The epic's Your part. Front matter `epic: test-speed` and `after: test-speed` (board/stories/README.md:51-61): it waits for the epic's code stories and does not hold the epic, so the epic can leave the board and v0.28.0 can be cut. The check needs v0.28.0 installed, so a plain lead story in the epic would hold its own precondition (board/epics/stage-gating.md:23). After the first real codex review under the installed v0.28.0 ends, the lead runs `ps -axo pid,ppid,command | grep tests/ | awk '$2 == 1'`. This story owns running the check. The release-v0.29.0 story's 'PPID-1 check' item (stage-gating.md:23) only quotes this story's recorded result and does not run it again. A non-empty result holds the v0.29.0 cut: the lead files the fix, and once it merges runs the check again after the next real review. **You:** none; the lead runs it.

Review fix (codex): a test can leave a child such as `sleep 30` with PPID 1 and no `tests/` in its command line. Before the review, record the PIDs of every process in the review's pane tree (herdr pane process-info); after it, list any of their descendants that are now orphaned (PPID 1), not only processes whose command names tests/.

**Done when:**
- The check, run right after the first real codex review under the installed v0.28.0 (or after the fix's merge, on a rerun), prints nothing, and that empty output is recorded where the release-v0.29.0 story's PR quotes it.

---
kind: code
status: ready
epic: flow-speedups
touches: [bin/swarm.sh:STALL_PY (stall_age signs), bin/swarm.sh:wait_agent (--stall signs), bin/swarm.sh:dash_slow or dash_fields (signs passed to the dash), tests/epic_test.sh (stall block), tests/dash_test.sh (stall rows), docs/method.md (stall_minutes row)]
---

# A builder editing files is not stalled

The stall rule's signs of life are events.tsv lines, the worktree's last commit and the PR's updatedAt. A builder that holds its whole diff uncommitted while it runs mutation tests or the full suite reads as stalled after stall_minutes: on 2026-10-15 close-takes-a-cause, dash-escalation and reconcile-keeps-board-edits all did, and each time a conductor had to read the pane and grant another window. Add the newest mtime among the worktree's changed and untracked files (from `git status --porcelain`, capped at a few hundred paths, ignoring .git) as one more sign, wherever stall_age's signs are gathered (wait --stall and the dash).

**Done when:**
- tests/epic_test.sh: with a busy session and every other sign older than stall_minutes (the last commit, events.tsv lines, and the wait's own start aged with SWARM_WAIT_STARTED as tests/dash_test.sh does), a builder with a file in its worktree modified a minute ago is not stalled: `wait --stall` runs to its timeout and does not exit 3. With that file's mtime set older than stall_minutes (touch -t), it exits 3, stalled.
- tests/dash_test.sh: the same two cases show working and stalled.
- A worktree with no changes behaves as today.
- docs/method.md's stall_minutes row names the new sign.
- The PR shows the first check failing with the new sign removed; shellcheck and every tests/*_test.sh pass.

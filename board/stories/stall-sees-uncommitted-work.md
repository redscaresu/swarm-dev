---
kind: code
status: ready
epic: flow-speedups
touches: [bin/swarm.sh:session_log (reused), bin/swarm.sh:STALL_PY (stall_age signs), bin/swarm.sh:wait_agent (--stall signs), bin/swarm.sh:dash_slow or dash_fields (signs passed to the dash), tests/epic_test.sh (stall block), tests/dash_test.sh (stall rows), docs/method.md (stall_minutes row)]
---

# A builder editing files is not stalled

The stall rule's signs of life are events.tsv lines, the worktree's last commit and the PR's updatedAt. A builder that holds its whole diff uncommitted while it runs mutation tests or the full suite reads as stalled after stall_minutes: on 2026-10-15 close-takes-a-cause, dash-escalation and reconcile-keeps-board-edits all did, and each time a conductor had to read the pane and grant another window. Add the newest mtime among the worktree's changed and untracked files (from `git status --porcelain`, capped at a few hundred paths, ignoring .git) as one more sign, wherever stall_age's signs are gathered (wait --stall and the dash).

**Done when:**
- tests/epic_test.sh: with a busy session and every other sign older than stall_minutes (the last commit, events.tsv lines, and the wait's own start aged with SWARM_WAIT_STARTED as tests/dash_test.sh does), a builder with a file in its worktree modified a minute ago is not stalled: `wait --stall` runs to its timeout and does not exit 3. With that file's mtime set older than stall_minutes (touch -t), it exits 3, stalled.
- tests/dash_test.sh: the same two cases show working and stalled.
- A worktree with no changes behaves as today.
- docs/method.md's stall_minutes row names the new sign.
- The PR shows the first check failing with the new sign removed; shellcheck and every tests/*_test.sh pass.

**From the lead (binding, 2026-10-15, after #143):** #143 gives the stall mark to every working agent, but a conductor in a foreground `wait`/`watch` writes nothing to events.tsv, and planners, skeptics, codex reviewers and the HLD co-writer never run swarm.sh, so each shows `stalled` after stall_minutes of normal work. Add one more sign for every agent with a recorded Claude session: the mtime of its session .jsonl (session_log finds it; a session writes to it on every turn and tool call). Extra Done when: in tests/dash_test.sh a working conductor and a working planner with no events.tsv lines for stall_minutes, whose session .jsonl was written a minute ago, show working, not stalled; with the .jsonl's mtime older than stall_minutes, they show stalled.

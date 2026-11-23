---
kind: code
status: later
fix: true
touches: [bin/lib/lifecycle.sh:close_agent, tests/close_test.sh]
estimate_lines: 120
easy: false
---

# close refuses to remove a worktree with unpushed work

From the v0.32.0 retro (2026-11-20 incident). `swarm.sh close <slug> paused` (bin/lib/lifecycle.sh `close_agent`) removed two ship-gates builders' worktrees and their unpushed branches; the lead meant only to restart them. Before close removes a story's worktree or branch for any cause, check for commits not on origin and for uncommitted changes. If there are any, keep the worktree and branch, say so on stderr with the path and the count, and close only the pane.

**Done when:**
- A close of a builder whose worktree has an unpushed commit leaves the worktree and branch in place and names them on stderr.
- A close with nothing unpushed and a clean tree removes them as today.
- Both cases are in tests/close_test.sh and fail when the check is removed.

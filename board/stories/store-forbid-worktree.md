---
kind: code
status: later
touches: [internal/adapter/store]
estimate_lines: 80
easy: true
---

# The Go store refuses a worktree of the forbidden checkout

From the v0.32.0 retro (#1142). The Go Appender under internal/adapter/store refuses SWARM_FORBID_PROJECT's own path but not a worktree of it; bash refuses both. Resolve a worktree to its main checkout before the compare, as bash does.

**Done when:**
- A test appends through a worktree of the forbidden checkout and is refused, and fails with the fix removed.
- An append to an unrelated project still works.

---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [close-spares-live-agents, restore-keeps-launch-flags]
touches: [bin/lib/lifecycle.sh:upgrade (new), bin/swarm.sh:usage, docs/reference.md, commands/swarm.md, tests/]
---

# swarm.sh upgrade moves a running epic to the installed version

On 2026-10-21 moving a running epic from 0.21.0 to 0.23.0 took the lead an hour by hand (report,
move it aside, close, start a fresh conductor, restart 12 builders in their worktrees) and lost every
builder by accident. `swarm.sh upgrade [<epic>]`, run after `claude plugin update`:

1. Asks the conductor to write a handover (each open PR's round, what its builder owes, unsent
   findings) to `.swarm/handover-<epic>-<date>.md`, and waits for it.
2. For each agent of the epic, when idle (`herdr agent wait`), sends ctrl+c, then restarts it in the
   same pane with `herdr agent start <n> --kind claude --pane <p> -- --resume <session id>` and the
   new version's flags (session id from `herdr agent list`'s agent_session, flags from
   `herdr pane process-info`). A resumed session keeps its context; only the plugin root changes.
3. Never touches a worktree: uncommitted and unpushed work stays as it is.
4. Prints each agent with its old and new version; `swarm.sh version` in each pane confirms it.

**Done when:**
- With a herdr stub holding a conductor and two builders, `upgrade` requests the handover, restarts all three with --resume and the new root, and leaves a dirty fixture worktree unchanged.
- A busy agent is waited for, not interrupted; one that stays busy past the timeout is named and left on the old version.
- docs/reference.md and commands/swarm.md describe it, and a test greps both.

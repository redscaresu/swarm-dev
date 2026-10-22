---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/session_mtime.py, bin/lib/agents.sh, tests/agent_liveness_test.sh]
estimate_lines: 150
easy: false
---

# A builder busy on a hung command is reported stalled, with the command, so the conductor can stop it

On 2026-10-22 the gh-graphql-budget builder sat busy for nearly three hours on a hung `watch` started by a test. `stall_minutes` (30) never fired. stall detection counts any write to the session log as a sign of life (session_mtime), and the hung session kept writing: "Compacted while idle" entries and background-task notices. The conductor's `tell findings` was refused as busy each time, and its wait timed out after an hour.

Two changes:
- session_mtime counts only entries that are the agent's own work: an assistant message, a tool call or a tool result. A compaction or summary entry, or a background-task notice, is not a sign of life.
- When `wait` finds a builder stalled, it lists the builder's longest-running child process (under its pane's shell: PID, minutes running, the command cut to 120 characters) in the `stalled?` line and in an `incident` line in events.tsv. The conductor then kills that PID. The conductor's brief says so: kill by PID, never pkill, then tell the builder what was killed and why.

**Done when:**
- A test in tests/agent_liveness_test.sh with a session .jsonl whose last own-work entry is 40 minutes old and whose newer entries are only compaction and task-notice entries reports `stalled?`. The same log with a 5-minute-old tool call does not.
- A test whose stub process tree holds a `sleep` started 45 minutes ago (faked through the ps stub) prints its PID, its minutes and `sleep` in the stalled line and the incident line.
- `make test` passes, and docs/reference.md's `stall_minutes` entry says what counts as a sign of life.

---
kind: code
status: later
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_queue, bin/lib/panes.py:prompt detection, commands/swarm.md:wait --lead handler, tests/stuck_work_watch_test.sh (new), docs/reference.md:wait --lead lines]
estimate_lines: 280
easy: false
---

# wait --lead wakes the lead for every kind of stuck work, not only stories with no agent

Target: v0.29.0 (user, 2026-10-26). On 2026-10-25/26 the user found these by hand, several times, while swarm.sh's waits saw nothing: builder panes frozen on a Claude Code permission prompt or the "Teach auto mode" dialog for hours (one from 03:07), a pane dropped into manual mode after a prompt was answered, PRs that passed review and were green but sat unmerged (#508 for 1h45, #539 for over an hour), PRs left conflicting with main, and main red after two individually-green PRs merged. The lead stopgapped it with .swarm/lead-watchdog.sh, a 3-minute poll; this story moves that into swarm.sh.

Add to lead_queue (so wait --lead, next and status all show it), each line naming its exit, each alerted once per occurrence:
- `prompt: <agent>`: its pane waits on a Claude Code permission prompt or dialog, or shows manual mode, or a login or API error. Exit: who answers it (the user), and for manual mode, restart the builder (no-agent-alert's restart command).
- `unmerged: <slug> <PR>`: passed review on its current head, green and mergeable, open for more than queue_minutes. Exit: swarm.sh merge with the reviewed head.
- `conflict: <slug> <PR>`: an open story PR CONFLICTING with the base. Exit: tell its builder to merge the base in.
- main red is already fix-main's; do not duplicate it.

Reads stay inside wait --lead's poll budget (one herdr agent list per poll; a per-pane read only for an agent herdr lists as blocked, idle or done).

**Done when:**
- A test per line kind fires on its real case and stays silent on its false case (a pane mid-command that is not a prompt; a PR passed review on an older head; a PR mergeable but not reviewed).
- commands/swarm.md's wait --lead handler has an arm for each new kind, and the handler-coverage test covers them.
- `make test` passes.

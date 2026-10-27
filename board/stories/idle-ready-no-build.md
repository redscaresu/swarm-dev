---
kind: code
status: blocked
epic: stuck-work
depends_on: [concurrency-check, idle-lines-in-lead-queue]
needs: [concurrency-check: touches_rows.py --idle by part and the next idle list as it leaves them (shared parts), idle-lines-in-lead-queue: SWARM_QUEUE_MINUTES, passed to touches_rows.py by idle_now]
touches: [bin/lib/touches_rows.py:--idle, commands/swarm.md:next idle list, tests/idle_ready_test.sh (new), docs/reference.md:idle lines]
estimate_lines: 130
easy: false
---

# idle: a ready story with no build past queue_minutes

Uses concurrency-check's --idle mode and next idle list (shared parts), and idle-lines-in-lead-queue's SWARM_QUEUE_MINUTES passed by idle_now. touches_rows.py --idle adds `idle: <story> is ready with no build, exit: <its conductor's, else swarm.sh story <slug>>` for a story that is ready and buildable, clashes by part with no running build, has no build started, and has been ready longer than queue_minutes (events.tsv and board state; no gh or herdr call). commands/swarm.md's next idle list gets an item for it.

**Done when:**
- tests/idle_ready_test.sh (new): such a story gives the line; a ready story clashing with a running build, one ready under queue_minutes, and one with a build started give none. Each check fails with its condition removed.
- commands/swarm.md's next idle list has the new line, checked against what touches_rows.py prints.

---
kind: code
status: ready
epic: stuck-work
depends_on: []
touches: [bin/lib/board.sh:idle_now (new), bin/lib/board.sh:idle_lines, bin/lib/lifecycle.sh:lead_queue, bin/lib/merge.sh:status_report, bin/lib/dash.sh:dash_render, bin/lib/dash_render.py:idle rows, commands/swarm.md:wait --lead handler, tests/lead_handler_test.sh:KINDS, tests/idle_queue_test.sh (new), docs/reference.md:wait --lead lines, docs/method.md:Every stop names its exit]
estimate_lines: 170
easy: false
---

# wait --lead, status and dash carry next's idle: lines

Today only next prints idle: lines (idle_lines, bin/lib/board.sh:426), and status and dash never read lead_queue (only wait --lead does, bin/lib/lifecycle.sh:2857). Add idle_now (board.sh, new): the one call of touches_rows.py --idle, with SWARM_AGENT_KINDS and SWARM_QUEUE_MINUTES (CFG_queue_minutes, for idle-ready-no-build), board and state only, no gh call. idle_lines, lead_queue, status_report (bin/lib/merge.sh:1817+) and dash_render (bin/lib/dash.sh:578, rows in bin/lib/dash_render.py) call it, so the lines are recomputed each poll and frame and so after each merge; in wait --lead each wakes the lead once per occurrence. commands/swarm.md's wait --lead handler gets one `idle:` arm: handle it as the next idle list says. lead_handler_test's KINDS gets idle. docs/method.md's 'Every stop names its exit' says wait --lead carries idle capacity. merge-holds' protected-hold-queue also edits lead_queue: story --strict serialises the two.

**Done when:**
- tests/idle_queue_test.sh (new): one blocked story whose dependency it does not use shows the same idle: line in `swarm.sh wait --lead 0` (once, not on the next poll), in `swarm.sh status` and in dash; after its dependency's merge is reconciled the line is gone from all three, and a story readied by that merge that has no build shows up. Each check fails with that report's idle_now call removed.
- tests/lead_handler_test.sh passes with idle in KINDS.

---
kind: code
status: blocked
epic: retro-report
depends_on: [retro-command]
needs: [retro-command (the section runner and its context (window day; events.tsv path))]
touches: [bin/lib/retro_incidents.py, tests/retro_incidents_test.sh, docs/reference-logs.md:incidents paragraph (swarm.sh retro part)]
estimate_lines: 140
easy: false
---

# retro's incidents list: every lead-hand and user-caught line in full

Needs from retro-command: the section runner and its context. Add bin/lib/retro_incidents.py. It prints every lead-hand and user-caught line since the window's day in full, oldest first, as local day, kind, cause and text. These are the lines `swarm.sh intervene` writes (bin/swarm.sh:573-595): incident, target -, outcome `<kind>: <text>`, cause=<cause>. After them come the other kinds flow_incidents.py counts (incident lines and stalled step-ups, flow_incidents.py:32-60). Each kind and cause is one row, with its count and its first and last day. Read each row with events_outcome's outcome and fields (bin/lib/events_outcome.py), and take days in local time, as flow_incidents does. flow's incidents section stays a count. If nothing is found, print a line saying so. Docs: fill only the **incidents** stub paragraph that retro-command wrote in docs/reference-logs.md's `### swarm.sh retro` part, and leave the other paragraphs alone. One sentence per line in docs (the coming 150-word line cap, board/stories/doc-line-cap.md).

**Done when:**
- tests/retro_incidents_test.sh (new) logs one lead-hand and one user-caught line with `swarm.sh intervene` in a fixture project. `swarm.sh retro` prints each line's full text with its day, kind and cause. The test fails if either text is missing.
- In the same test, a hand-written intervene line dated before the window does not appear. A `wait-timeout` incident appears as one row with count 1.
- tests/incidents_test.sh passes with no change to it. The new test fails on a worktree copy that prints counts only, and the PR body has the FAIL lines.

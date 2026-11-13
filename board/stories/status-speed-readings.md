---
kind: lead
status: ready
epic: status-speed
after: status-speed
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: time status on the real board, read the median, and settle the epic's changes with the user

The epic's Done when wants flow run_times' median under 30 s, and every story proves its speed on a fixture. Once every status-speed story has merged and the lead runs a plugin with them: run `SWARM_REPORT_TIMES=1 SWARM_RUN_TIMED=1 swarm.sh status` once on the real board and record the section times with the 1-minute load; then `gh api rate_limit` and `swarm.sh flow --since <last merge day>` once, and record run_times' median per load band with its runs. The plan narrows the epic: status gets no reuse across runs, next gets no budget, dash gets no target, and the median moves to this reading. **You:** agree that, or say what to add back; the same board PR edits board/epics/status-speed.md to match.

**Done when:**
- The real-board section times and the median per load band, with runs and window, are recorded in the PR that finishes this story or the v0.31.0 checkpoint file, against the 30 s bar.
- The user's answer is recorded and board/epics/status-speed.md matches it.

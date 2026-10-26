---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/log_turn_over.py:ended, bin/lib/agents.sh:note_wake_now, tests/tell_note_test.sh:background shell case]
estimate_lines: 120
easy: false
---

# A note wakes a conductor idle between turns with background shells running

v0.28.0 retro: notes to conductors idle with background shells sat unread in .swarm/inbox for over an hour. note_wake_now (agents.sh:1523-1545) prompts only when upgrade_state says idle. A busy session counts as idle only when turn_over (log_turn_over.py) sees the log end on an end_turn assistant entry with no later user entry. tell_note_test already claims that case works (tell_note_test.sh:2-5), so reproduce the real one first. The builder never reads ~/.claude/projects. The lead puts a redacted session-log entry (keys and shape only) of what a background shell writes after end_turn in the build brief. Build the fixture from it, then fix the turn-ended detection.

**Done when:**
- tests/tell_note_test.sh: a conductor whose log ends with the entry shape from the brief after end_turn gets the wake prompt; the test fails on the code before the fix (shown in the PR).
- A conductor mid-turn (a tool call waiting on its result) still gets no prompt; the existing cases pass.

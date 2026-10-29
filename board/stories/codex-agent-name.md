---
kind: code
status: later
depends_on: []
touches: [bin/lib/lifecycle.sh:wait_lead story-file reads]
estimate_lines: 60
easy: true
---

# wait --lead prints no sed or awk noise after a merge removes a story file

- wait --lead prints `sed:` or `awk: can't open file board/stories/<slug>.md` when a merge removes a story file between its list and its read.

**Done when:**
- A test removes a story file mid-poll, and wait --lead prints no sed or awk error.

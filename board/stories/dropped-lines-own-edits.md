---
kind: code
status: ready
fix: true
touches: [bin/lib/dropped_lines.py:scan, bin/lib/dropped_lines.py:extended, tests/dropped_lines_test.sh]
estimate_lines: 150
easy: false
---

# dropped-lines holds a PR for base lines its own commits changed

From the v0.32.0 retro (#1042, #1068, #1169). dropped-lines (bin/lib/dropped_lines.py `scan`) holds a PR when its merge of the base drops a base line its head has not put back. It also holds a PR whose own non-merge commits reworded or extended that line on purpose: #1042 extended a line, #1068 reworded ten, #1169 rewrote eight comment lines. Each cost the user a hand merge. Tell the two apart: a base line that the PR's own commits (not its merges of the base) changed, against the merge base, is the PR's edit and is not held. A line dropped only by a merge of the base stays held.

**Done when:**
- A fixture PR whose own commit rewords a base line passes dropped-lines; it was held before.
- A fixture PR whose merge of the base drops a base line that no commit of its own touched is still held.
- Both cases are in tests/dropped_lines_test.sh and fail when the fix is removed.

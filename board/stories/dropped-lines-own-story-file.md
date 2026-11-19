---
kind: code
fix: true
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:scan own story file, bin/lib/merge.sh:dropped_hold story file, tests/dropped_lines_test.sh:own story file cases, docs/reference-merging.md:Held for dropped base lines own story file sentence]
estimate_lines: 120
---

# dropped-lines skips a story PR's own story file when the PR deletes it

From the v0.31.2 run (2026-11-18). Board PR #1002 added `fix: true` to six story files after their
branches were cut. A story PR deletes its own story file, so when a builder merged main in and kept
the deletion, `swarm.sh merge` held the PR as "dropped base lines" for that file's new line. It hit 3
of the 8 v0.31.2 PRs (#1003, #1006, #1008), and each was cleared by hand with a commit that put the
file back. The user chose (2026-11-19) to fix it in bash now, before the v0.32 freeze, so the Go
rewrite does not carry the false hold for its whole run.

Change `swarm.sh dropped-lines` (bin/lib/dropped_lines.py, called through dropped_hold in
bin/lib/merge.sh) so a line in `<board>/stories/<slug>.md`, where `<slug>` is the PR's own story,
does not count as dropped when the PR's head deletes that file. Every other file, and the PR's own
story file when the head keeps it, counts as today. A PR with no story (a board PR, a lead's PR)
counts every file as today.

**Done when:**
- tests/dropped_lines_test.sh: a fixture story PR whose merge of the base kept the deletion of its own
  story file, after the base added a line to it, prints no dropped line for that file and merge does
  not hold it; with the change removed it is held (shown on a worktree copy, quoted in the PR)
- The same fixture with a dropped line in another file, or in another story's file, is still held
- A PR whose head keeps its own story file and drops a line of it is still held
- docs/reference-merging.md's "Held for dropped base lines" paragraph says a PR's own deleted story
  file is skipped, with the v0.31.2 holds as why
- scripts/select-tests.sh --run passes

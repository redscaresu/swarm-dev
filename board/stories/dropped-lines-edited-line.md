---
kind: code
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:edited-line check, tests/dropped_lines_test.sh:edited-line cases, docs/reference-merging.md:dropped-lines paragraph (§ Merging) edited sentence]
estimate_lines: 90
easy: true
risk: high
---

# The dropped-lines check skips a base line the PR's head extends

On 2026-11-15 `swarm.sh merge` held #937 (flow-panes) for its `swarm.sh flow` row in docs/reference-logs.md.
The PR added a `panes` section to that row on purpose. A word diff of main's row against the head's shows
one insertion and nothing removed, yet bin/lib/dropped_lines.py reports the row as dropped, since main's
exact line no longer appears. Even after #953 (restored lines), main's check still flags it. The same
kind of hold has sent PRs to the user by hand several times (the machine-usable report, 2026-11-15).

After the per-merge scan and #953's restored-line pass, drop a reported line L of file F when the PR's
head holds a line in F that contains every word of L in the same order (L's words are a subsequence of
the head line's words), and no other reported line already claimed that head line. A line whose words
were changed or removed keeps printing. This check is a safety rail, so prove each case on a fixture.

**Done when:**
- tests/dropped_lines_test.sh: a fixture where main adds line L and the PR's merge of main replaces it with
  L plus inserted words prints nothing and exits 0
- A fixture where the PR's version of L drops or changes one of L's words still prints L and exits 1
- A fixture where two base lines are both extended into one head line still prints one of them
- Every existing case in tests/dropped_lines_test.sh still passes, including the both-sides, inherited
  and restored cases
- The first case goes red with the change removed, and the second and third stay red with it in, shown
  on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-merging.md's dropped-lines paragraph says a line the head extends without dropping a
  word does not count
- scripts/select-tests.sh --run passes

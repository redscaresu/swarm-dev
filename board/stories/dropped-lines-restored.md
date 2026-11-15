---
kind: code
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:head copies count, tests/dropped_lines_test.sh:restored-later cases, docs/reference-merging.md:dropped-lines paragraph (§ Merging) restored sentence]
estimate_lines: 70
easy: true
risk: high
---

# The dropped-lines check skips a line the PR's head still holds

On 2026-11-15 swarm.sh merge held #826 (pane-close-event) for 1 dropped line in docs/reference-models.md (the `stall_minutes` bullet). Merge 1805b54 dropped it, and the builder's later commit put it back: the PR's head and main each hold the line exactly once. bin/lib/dropped_lines.py checks each merge commit alone and reports a line a merge dropped, even when a later commit on the branch restored it. So a PR whose builder fixed its own merge is still held for a person.

After the per-merge scan, drop a reported line L of file F when the PR's head holds at least as many copies of L in F as the base does at the PR's merge base with it. A line still missing at the head keeps printing. This check is a safety rail, so prove each case on a fixture.

**Done when:**
- tests/dropped_lines_test.sh: a fixture where a merge of main drops line L and a later commit on the branch adds L back (the head and the base each hold one copy) prints nothing and exits 0
- A fixture where the merge drops L and nothing restores it still prints L and exits 1
- A fixture where the base holds two copies of L, the merge drops both and a later commit restores only one still prints L once
- Every existing case in tests/dropped_lines_test.sh still passes, including the both-sides and inherited cases
- The first case goes red with the change removed, and the second and third stay red with it in, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-merging.md's dropped-lines paragraph says a line the head still holds does not count
- scripts/select-tests.sh --run passes

---
kind: code
status: ready
depends_on: []
touches: [bin/lib/dropped_lines.py:sides stacked-parent merge, tests/dropped_lines_test.sh:stacked-parent cases, docs/reference-merging.md:dropped-lines paragraph (§ Merging) stacked sentence]
estimate_lines: 100
easy: false
risk: high
---

# The dropped-lines check follows a merge of a stacked parent's branch once that parent has merged

Four story PRs stopped their review on the same refusal between 2026-11-15 and 2026-11-16: #879, #909,
#956 and #905. Each had been stacked on a parent story, merged the parent's branch while stacked, and
kept that merge on its first-parent chain after the parent merged to main. bin/lib/dropped_lines.py's
`sides` then finds neither parent of that merge on the base (`merge <sha> is unchecked: neither parent
is on <base>, so it is not a merge of <base> (a stacked build's merge of its parent branch?)`), so
`swarm.sh merge` cannot check the PR and holds it. The review agent stops on every head. Each time, the
lead had the builder rebuild the branch as one commit on main and force-push, which cost a review
round and a CI run, plus the hours each PR sat stopped.

When a merge's second parent is on a branch whose PR has merged to the base (the parent story's squash
merge holds that branch's tree change), treat the merge as a merge of that parent's branch: check the
lines it drops against the parent branch's head, as the check already does for a merge of the base, and
report only lines that neither the parent branch nor the base still holds. A merge whose parents are
both unknown still stops with today's message. This check is a safety rail, so prove each case on a
fixture.

**Done when:**
- tests/dropped_lines_test.sh: a fixture where a story branch merges its parent's branch, the parent then
  squash-merges to main, and the story then merges main, with no line lost, prints nothing and exits 0;
  with the change removed it prints the "neither parent is on" refusal (shown on a worktree copy and
  quoted in the PR, AGENTS.md mutation rule)
- The same fixture where the merge of the parent's branch drops a line that main and the parent's branch
  both still hold prints that line and exits 1
- A merge whose second parent is on no merged PR's branch still stops with today's message
- Every existing case in tests/dropped_lines_test.sh still passes, including the both-sides, inherited,
  restored and edited-line cases
- docs/reference-merging.md's dropped-lines paragraph says a merge of a merged parent's branch is
  checked against that branch, and names the four PRs above as why
- scripts/select-tests.sh --run passes

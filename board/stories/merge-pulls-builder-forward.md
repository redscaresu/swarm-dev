---
kind: code
status: ready
fix: true
depends_on: []
touches: [bin/lib/merge.sh:pull_first builder worktree, tests/merge_pull_forward_test.sh, docs/reference-merging.md:§ Merging builder pull sentence]
estimate_lines: 150
---

# After merge has GitHub merge the base into a story PR, it pulls the builder's worktree forward

From the v0.31.x run (2026-11-15 to 2026-11-18). When `swarm.sh merge` finds the base moved, merge_base_update
(bin/lib/merge.sh) has GitHub merge the base into the PR's branch. The PR's head is then GitHub's merge
commit, which the builder's worktree lacks. When that merge run then refuses (`base merge unchecked:`, a red
CI on the new head, `base merged, still moving:`), every refusal ends with pull_first's text, and nothing
acts on it: the review agent refuses to start because the worktree is not at the PR's head, and the lead
pulls or tells the builder by hand. This stalled 7 of the 35 merges between v0.30.3 and v0.31.1: #914 four
times, #987 three times, and #964, #970, #974, #992 and #997.

Make merge act on it. Once a story PR's head is GitHub's merge of the base (the head merge_base_update
recorded as `base-merged`), and before merge returns, refusal or not: when the story's worktree is clean and
at the PR's old head, merge fetches and fast-forwards it to the new head (`git -C <worktree> merge --ff-only`),
and prints one line saying so. When the worktree has uncommitted changes, is at another commit, or the
fast-forward fails, merge leaves it as it is and sends the builder a nudge through `swarm.sh tell <slug> nudge`
that names the new head and says to `git pull --ff-only` before its next push. A PR with no story worktree
(a board PR, a lead's PR) is left as today. pull_first's text stays on the refusal.

**Done when:**
- tests/merge_pull_forward_test.sh: a fixture story whose PR head became GitHub's merge of the base, with a
  clean worktree at the old head, ends with the worktree at the new head after a merge run that refuses;
  with the change removed the worktree stays at the old head (shown on a worktree copy, quoted in the PR)
- The same fixture with an uncommitted change in the worktree leaves the worktree as it was and queues one
  nudge for the builder naming the new head
- A board PR's merge touches no worktree and sends no nudge
- docs/reference-merging.md § Merging says merge pulls the builder's worktree forward, or nudges the builder,
  after a base merge, with the 7 stalled merges as why
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
blocked_by: [close-takes-a-cause]
epic: flow-speedups
depends_on: [close-takes-a-cause]
touches: [bin/swarm.sh:reconcile (pre-pull cleanup), bin/swarm.sh:clear_build (reused; why text for a merge or a closed PR), tests/epic_test.sh (new reconcile cleanup block), docs/method.md (§ Building, **Clean up.** and the reconcile sentences in **Merging.**), README.md (only if it describes the manual cleanup)]
risk: high
---

# reconcile clears a story's build away once its PR merges, or closes unmerged with no builder open, so the lead's manual cleanup goes and the story can be built again

Absorbs the board story of the same slug and adds `epic: flow-speedups`. Story items only, not epics. Before the pull, while the story file still exists and gives `repo:`, reconcile does two things. (1) For a merged story whose builder is open (agent_field pane_id), it closes it with close_agent, which counts nothing because the status is review, then clears the worktree, local and origin story/<slug> through clear_build as #131 left it (`<slug> <why> <prs>`, prs `[]` so it closes no PR). (2) For a story it sends back to ready from a closed PR, it does the same clearing only when no builder is open. Otherwise it leaves everything and prints a line naming the slug. `story` deletes nothing. Herdr calls happen only under HERDR_ENV=1: the reconcile arm has no require_herdr, and review_test runs it with only a gh stub. method.md § Clean up says reconcile does this now.

**Done when:**
- tests/epic_test.sh: a story PR closed unmerged (stubbed gh), then `reconcile` with no builder open. The worktree dir, local story/<slug> and origin's story/<slug> (seeded in the bare origin) are gone, `story <slug>` succeeds, and its builder can push story/<slug>.
- With that builder still open, reconcile leaves the worktree and both branches, and prints a line naming the slug.
- A story in review whose PR merged, with its builder open in the herdr stub: reconcile closes its pane (herdr.log), removes the worktree and both branches, and finishes the story. attempts: is unchanged, and no gh pr close is called.
- tests/review_test.sh's existing reconcile cases pass unchanged, with no herdr stub on PATH.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- A merged story's build is always cleared (worktree, local and origin story/<slug>), whether or not its builder is open; close_agent runs first only when one is open. Only the closed-unmerged clear is gated on no builder being open.
- Do the close and the clear in reconcile's first per-item loop, before the committed-status restore (bin/swarm.sh:2341). Without HERDR_ENV, treat it as no builder open.
- Extra Done when: a merged story with no builder open still loses its worktree and both branches; with goal = 5, the board in the repo and the review status uncommitted, reconcile exits 0 and closes the open builder; a second reconcile is a no-op.
- Put the new tests/epic_test.sh block somewhere other than the end of the file (codex-time-limit also appends there).

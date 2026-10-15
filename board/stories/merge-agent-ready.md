---
kind: code
status: blocked
blocked_by: [goal-conductor-rule, codex-time-limit, story-after-unmerged-close, reconcile-keeps-board-edits]
epic: flow-speedups
depends_on: [goal-conductor-rule, codex-time-limit, story-after-unmerged-close, reconcile-keeps-board-edits]
touches: [bin/swarm.sh:conduct_merge_rule (agent branch), bin/swarm.sh:conduct_epic_mode (merge_step, agent branch), bin/swarm.sh:start_agent (merge guard), bin/swarm.sh:merge_rule (agent wording), tests/epic_test.sh (conductor-brief checks), tests/review_test.sh (merge guard block), commands/swarm.md (story arm, merge = agent sentences), docs/method.md (§ Building, **Merging.**, the merge = agent part)]
risk: high
---

# With merge = agent the conductor merges a pinned head by literal PR number, starts the stories that merge readied in the same run, and only it can merge

Only the merge = agent branches change. With human, the briefs and start args stay as they are. conduct_merge_rule (agent): note the head SHA the review passed on (`gh pr view <n> --json headRefOid`), then merge by the literal PR number with `--match-head-commit <sha>` and the repo's merge method flag, never --auto: the block-red-pr-merge hook needs a literal number and every check complete. If the head moved, review it again. Then review and reconcile, which now closes the builder (so the separate `close <slug>` goes), then unblock, and start each story of this epic that unblock printed as `ready:` whose touches do not overlap a running one, in this run. Report only when no story of the epic is ready or running. conduct_epic_mode's merge_step (agent) and commands/swarm.md's story arm (agent) get the same pinning. start_agent keeps the merge-disallowing `--disallowedTools` guard on every role except conduct when merge = agent. merge_rule (agent) says the conductor merges. method.md § Merging (agent) matches.

**Done when:**
- tests/epic_test.sh, conductor-brief checks: with merge = agent, the story-mode brief contains `--match-head-commit`, 'literal', 'never --auto' and an instruction to start the stories unblock prints as ready in the same run. The epic-mode brief contains `--match-head-commit`. With merge = human, neither brief contains `--match-head-commit`, and the existing human checks pass unchanged.
- tests/review_test.sh merge guard (:214-227): with merge = agent, a story builder's `agent start` line still has the merge-disallowing `--disallowedTools` guard, and a conductor's (`conduct e`) does not. With merge = human, both have it.
- grep finds `--match-head-commit` in commands/swarm.md's story arm.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Depends on reconcile-keeps-board-edits too: the in-run merge, reconcile, unblock loop leaves unblock's flips in the board for the next pull.
- The brief tells the conductor how to find the merge method: `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` (squash when allowed). A Done when checks the brief contains it.
- SHA pinning in order: capture the head SHA before review, review that SHA, compare the PR head afterwards, and restart review on any change; merge with `--match-head-commit <captured sha>` and a literal PR number.
- Only the conductor role loses the merge guard; builders and planners keep it (bin/swarm.sh:641-643), and tests/review_test.sh:225-227 changes to pin that.
- Literal brief checks, each failing with its text removed: with merge = agent the story-mode brief contains `ready:` beside `swarm.sh story`; it contains no `swarm.sh close <slug>` after the merge (reconcile closes the builder); it states the report condition (no story of the epic ready or running).
- Starting newly ready stories yields to goal_rule: after a cleared-on-error or a give-up, start nothing more in the wave; a check pins this.
- commands/swarm.md's story arm with merge = agent drops its `swarm.sh close <slug>` after reconcile too (commands/swarm.md:80-84).
- Main is checked after every merge (ruleset-not-strict removed the up-to-date rule; on 2026-10-15 #134 and #137 were each green alone and main went red once both landed, fixed by #141). After each merge the conductor waits for CI on the merge commit on main, with a time limit; if it is red it merges nothing more, finds the PR pair, opens the fix (or lists it for the lead) and says so in its report. The brief contains this rule, and a check fails with it removed.

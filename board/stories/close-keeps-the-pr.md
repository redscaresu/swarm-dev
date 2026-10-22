---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/lifecycle.sh:close_agent, tests/close_test.sh, docs/reference.md:Cleanup]
easy: true
estimate_lines: 80
---

# close stops a builder's agent without closing its open PR, unless asked to

On 2026-10-22 the lead ran `swarm.sh close` on two idle builders (#360, #365) to move them onto 0.25.0. close_agent (bin/lib/lifecycle.sh:403) also closed both PRs and deleted their branches and worktrees, two review rounds' worth of work. The lead had to restore the branches from GitHub's refs/pull/<n>/head and reopen the PRs.

`swarm.sh close <builder>` closes the agent and its pane only. An open PR, its branch and its worktree stay, and close prints that the story stays in review with its PR. Sending a story back to ready (closing the PR, deleting the branch) takes `close <slug> --drop`, and it prints what it closed and deleted, with the head SHA so the work can be restored. Where conductors and the docs use close to drop a story today, they switch to `--drop`. Check every caller in bin/ and the briefs.

**Done when:**
- tests/close_test.sh, with stub gh: `close <builder>` with an open PR closes no PR, deletes no branch, keeps the worktree, and names the PR. `close <builder> --drop` closes the PR, deletes the branch and prints the head SHA.
- Every brief and doc that means "drop the story" says `--drop`.

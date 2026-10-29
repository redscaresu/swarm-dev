---
kind: code
status: ready
epic: rules-file
depends_on: []
risk: high
touches: [hooks/merge-guard.sh:check_git, tests/merge_guard_test.sh:main checkout cases, AGENTS.md:Rules that are not negotiable (the guard bullet), docs/reference.md:Merging (the lose-work paragraph), README.md:Cost and safety]
estimate_lines: 180
easy: false
---

# The guard refuses a reset, restore or clean that drops edits in the main checkout

Needs nothing from another story. This is Appendix B's item: syncing the main checkout never drops board edits wholesale (0.28 HLD:781). swarm.sh's own syncs already keep them: pull_board_repo refuses a checkout with commits the base lacks (bin/lib/lifecycle.sh:380-385), and reconcile names a field the pull replaced (:445). The guard refuses a git checkout over uncommitted changes in every session (hooks/merge-guard.sh:356-358). It refuses reset --hard, restore and clean in the main checkout only for an agent (merge-guard.sh:351-355), so the lead's hand reset drops board edits unseen. Extend check_git: in any session, in a swarm project's main checkout, refuse `git reset --hard`, `git restore` of the working tree (not --staged alone) and `git clean` without -n or --dry-run when it would drop an uncommitted change there, or, for clean, an untracked file. The refusal names the paths and the way out: commit them in a board PR, or back them up with cp. A clean main checkout and any worktree pass. An agent's commands are refused as today. Update AGENTS.md's guard bullet in Rules that are not negotiable (AGENTS.md:105-108), docs/reference.md § Merging's lose-work paragraph (:3142-3152) and README.md § Cost and safety (:164). Risk high: the guard is a safety path. Skeptic review (2026-10-29): detect exactly what the command would drop, never by a heuristic. For `git clean`, run `git clean -n` with the user's own flags (minus -f and -i) and refuse when it lists anything, ignored files included under -x or -X: `git status --porcelain` never shows ignored files, and init gitignores .swarm/ (bin/lib/lifecycle.sh:2237). For `reset --hard`, count staged and unstaged changes to tracked files (drops_changes counts a staged-only change only when checking out from a commit, hooks/merge-guard.sh:383), and leave untracked files out, since reset --hard keeps them: a new, uncommitted story file must not block every reset. `git restore` passes only when it touches the index alone: `--staged` or `-S` with no `--worktree` or `-W`; `git restore --staged --worktree f` and `-SW f` are refused like any other restore. 'A swarm project's main checkout' is the git top level of a directory holding .claude/swarm/config that is not a linked worktree (its .git is a directory), so the lead, who has no agent home (merge-guard.sh:300), is covered.

**Done when:**
- In tests/merge_guard_test.sh, in a session without SWARM_AGENT, in a swarm project's main checkout with an uncommitted edit to a board file, `git reset --hard`, `git restore <that file>` and `git restore .` are refused, naming the file. With an untracked new story file there, `git clean -fd` is refused and `git clean -n` passes.
- The same commands pass in a clean main checkout and in a worktree. `git restore --staged <file>` passes. An agent's reset --hard in the main checkout is still refused.
- Each new refusal's test goes red with its condition removed; the FAIL lines are in the PR body.
- AGENTS.md, docs/reference.md § Merging and README.md § Cost and safety name the new refusal; tests/doc_check_test.sh passes.
- `git clean -fdx` in a main checkout whose only change is an ignored file under .swarm/ is refused; `git reset --hard` with only a staged change is refused; with only an untracked new file it passes; `git restore --staged --worktree f` and `git restore -SW f` are refused.

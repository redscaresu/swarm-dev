---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [merge-guard-hook]
touches: [bin/lib/merge.sh:merge-guard, hooks/hooks.json, tests/merge_guard_test.sh]
risk: high
easy: false
estimate_lines: 150
---

# The plugin's guard hook protects the main checkout from agents

From the lead's memory (memory-rules-into-framework): a review agent once detached the main checkout, a `git checkout <file>` once wiped uncommitted work, and a failed `cd` followed by `;` once ran a `cp` in the main checkout. merge-guard-hook ships a PreToolUse hook in the plugin; this story widens it. Inside a swarm agent's pane (SWARM_AGENT set), a Bash command whose working directory, or whose `cd`/`-C` target, is the project's main checkout exits 2 when it runs `git checkout`, `git switch`, `git restore`, `git reset --hard`, `git stash` or `git clean`. Anywhere, `git checkout -- <path>` or `git checkout <path>` on a file with uncommitted changes exits 2 with "back up with cp, then restore from the copy". A `cd <dir>` followed by `;` exits 2 with "use `cd <dir> || exit 1 &&`". The lead's own session (SWARM_AGENT unset) is blocked only by the `cd ;` and dirty-file rules.

**Done when:**
- tests/merge_guard_test.sh feeds the hook JSON and expects exit 2 for: an agent running `git checkout main` in the main checkout; `git -C <main checkout> restore x`; `git checkout -- f` on a dirty f; `cd /nope; cp a b`.
- The same commands in a story worktree, `git checkout -- f` on a clean f, and `cd d || exit 1 && cp a b` exit 0.
- The test reads the hook's command from hooks/hooks.json, as merge-guard-hook's test does.

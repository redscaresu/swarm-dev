---
kind: code
status: blocked
blocked_by: [merge-command]
epic: lead-loop
depends_on: [merge-command]
touches: [bin/swarm.sh:board_pr (new), bin/swarm.sh:dispatch (board-pr arm), bin/swarm.sh:usage header, tests/board_pr_test.sh (new), docs/method.md (§ Who does what, board edits), commands/swarm.md (board edits)]
---

# swarm.sh board-pr makes the lead's board edits in their own worktree, never in the main checkout

The lead edits the board through a PR many times a day (unblocks, new stories, re-scopes). Today each is hand-built: worktree off origin/main, edit, commit, push, open the PR, clean up. On 2026-10-15 a failed `git worktree add` (error sent to /dev/null) and a `;` let a `cp` run in the main checkout and overwrite a tracked board file. `swarm.sh board-pr start <name>` creates `<repo>-wt/board-<name>` on a new `board/<name>` branch from origin/<base> and prints its path; it refuses when the branch or directory exists, and when the main checkout is the target. `swarm.sh board-pr open <name> "<title>" <body-file>` refuses unless every changed file is under the board dir, commits (with the project's commit trailers from the brief), pushes and opens the PR, printing its URL. `swarm.sh board-pr done <name>` removes the worktree and branch once its PR has merged or closed, and refuses otherwise. Each step logs one events.tsv line (board-pr:start|open|done, target name, ok or the refusal).

**Done when:**
- tests/board_pr_test.sh with a stub gh and a bare origin: `start x` creates the worktree on board/x from origin/main and prints its path; a second `start x` refuses and changes nothing; the main checkout's files are byte-identical before and after a full start, edit, open and done cycle.
- Failure cases, each refusing with no path printed, exit non-zero and the main checkout's tracked files unchanged: the target directory already exists (no branch); the target resolves to the main checkout (a symlink or `..` path); `git worktree add` fails (a bad base ref). Each check fails with its guard removed.
- `open x` refuses when a changed file is outside the board dir (e.g. bin/swarm.sh), opens nothing and logs the refusal; with only board files, it pushes board/x and calls gh pr create once.
- `done x` refuses while the PR is open; after the stub reports MERGED, it removes the worktree and both branches.
- Each events.tsv line exists with its outcome; a refusal leaves exactly one line.
- docs/method.md and commands/swarm.md say the lead's board edits go through `swarm.sh board-pr`.
- The PR shows each new check failing with its guard removed; shellcheck and every tests/*_test.sh pass.

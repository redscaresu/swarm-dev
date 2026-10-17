---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [board-state-out-of-git, escalated-block-out-of-git, pr-removes-story]
touches: [bin/lib/board.sh:reconcile, bin/lib/lifecycle.sh:pull_board_repo and its helpers, docs/reference.md:§ Building reconcile paragraph (reference.md:704-708), tests/reconcile_pull_test.sh (new), tests/epic_*_test.sh:reconcile cases, tests/review_test.sh:reconcile cases]
risk: high
easy: false
estimate_lines: 200
---

# reconcile loses its backup-and-restore, clears state for items that are gone, and logs a failed pull

Needs board-state-out-of-git (fields in .swarm/state), escalated-block-out-of-git (the block in state) and pr-removes-story (finish and drop through a board PR), so swarm.sh leaves no edit in the main checkout. reconcile in bin/lib/board.sh and pull_board_repo in bin/lib/lifecycle.sh: delete the backup and restore, swarm_edit, key_clash, keys_back, fm_rest and board_edits_named (bin/swarm.sh:4319-4432), and reconcile's own save and restore (:3674-3690). When the main checkout has tracked board edits, the pull stops and names them, and logs event incident with result `pull-failed: <files>`. reconcile deletes the state files of an item whose file is gone. About 125 of the lines are deletions. risk high: the pull is the step that broke on infrafactory #597.

**Done when:**
- tests/reconcile_pull_test.sh: a story marked review, then deleted by a merged PR on the fixture remote, pulls through reconcile with no backup, stash or error, and its state files are gone.
- The same test: a hand edit to a tracked story stops the pull, names the file, and writes one incident line `pull-failed`.
- grep finds none of swarm_edit, key_clash, keys_back, fm_rest, board_edits_named or reconcile-backup in bin/.
- Every tests/*_test.sh passes.

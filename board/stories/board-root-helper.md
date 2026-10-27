---
kind: code
status: blocked
epic: shared-helpers
depends_on: [contents-reader, reconcile-pulled-finish, builder-test-lines, init-auto-mode-check, board-pr-kinds]
needs: [contents-reader: bin/lib/board.sh:pr_hld as it leaves it (shared part), reconcile-pulled-finish: bin/lib/board.sh:drop_gone_state as it leaves it (shared part), builder-test-lines: bin/lib/build.sh:story_brief as it leaves it (shared part), init-auto-mode-check: bin/lib/lifecycle.sh:init_project as it leaves it (shared part), board-pr-kinds: bin/lib/lifecycle.sh:board_pr as it leaves it (shared part)]
touches: [bin/swarm.sh:board_rel (new), bin/lib/merge.sh:merge_pr, bin/lib/merge.sh:ready_tell, bin/lib/merge.sh:ignore_fixes, bin/lib/merge.sh:board_paths, bin/lib/merge.sh:release_grant, bin/lib/board.sh:release_due, bin/lib/board.sh:release_stage, bin/lib/board.sh:epic_unticketed, bin/lib/board.sh:pr_hld, bin/lib/board.sh:drop_gone_state, bin/lib/lifecycle.sh:board_pr, bin/lib/lifecycle.sh:pull_board_repo, bin/lib/lifecycle.sh:init_project, bin/lib/build.sh:story_path, bin/lib/build.sh:story_brief, tests/board_rel_test.sh (new)]
estimate_lines: 130
easy: false
risk: high
---

# One helper for the board's path in the repo, replacing 15 inline copies

Uses contents-reader's pr_hld, reconcile-pulled-finish's drop_gone_state, builder-test-lines' story_brief, init-auto-mode-check's init_project and board-pr-kinds' board_pr as they leave them (shared parts). Add board_rel (bin/swarm.sh, beside abs_path :295): the board's path from the project root with a trailing /, empty for a board at the root, worked out from BOARD when called (init_project resolves BOARD after making it). Replace the inline copies: bin/lib/merge.sh merge_pr :278 (the --board path check; ${rel%/} where no slash is wanted), ready_tell :556, ignore_fixes :755, board_paths :790, release_grant :1299; bin/lib/board.sh release_due :614, release_stage :639, epic_unticketed :917, pr_hld :1125, drop_gone_state :1860; bin/lib/lifecycle.sh board_pr :84, pull_board_repo :323, init_project :1936; bin/lib/build.sh story_path :307, story_brief :402. ci_gate.py keeps the prefix in Python; the shell passes it as today. Other epics' stories that edit the same parts (merge_pr, ready_tell, pr_hld, epic_unticketed, drop_gone_state, board_pr, init_project, story_brief) are serialised by `swarm.sh story --strict`; order does not matter for them.

**Done when:**
- tests/board_rel_test.sh (new) checks board_rel for a board at the root, at docs/, at a/b/, and through a board_dir with ..; it fails when board_rel drops or doubles the trailing /.
- merge --board still refuses a PR that changes a file outside the board, with the board at docs/ and at the root (the cases in tests/merge_test.sh or tests/board_only_test.sh pass).
- The diff replaces each of the 15 copies with board_rel.

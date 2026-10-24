---
kind: code
status: blocked
epic: plan-hld
depends_on: [next-plan-hld]
touches: [bin/lib/board.sh:finish_item and remove_item and drop_story, tests/pr_removes_story_test.sh]
estimate_lines: 100
easy: false
---

# swarm.sh finish <hld> deletes a planned HLD in a board PR once none of its epics is left

Needs hld_epics and hld_planned from next-plan-hld (bin/lib/board.sh). Run the epic's **Checks before every stage**.

finish_item (board.sh:791) resolves `<board>/hld/<arg>.md` when no story or epic has that slug. Before board_pr start, so nothing is left behind, it refuses: a draft HLD (the user's); an HLD with no `planned:` (agreed but never planned, so finishing it would drop work nobody did); and an HLD while hld_epics lists an epic, naming them. After board_pr start it checks again in the worktree's `<board>/epics` (origin's base, which remove_item treats as the truth, board.sh:807): on an epic carrying the `hld:` there, it unstarts and dies, as :807 does. That catches an epic merged on origin and not yet pulled.

remove_item takes the file from its caller, so item_file stays stories and epics only for every other command; drop_story (board.sh:877) calls remove_item too and changes with it. On an in-repo board this opens board PR `finish-<hld>`, titled `Finish <hld>`; a board outside the repo deletes in place (delete_item). hld/ is already board-only (bin/lib/merge.sh:690). pr_hld keeps a PR that deletes an HLD under none, so the user merges it under merge = human. The `finish ok` events line counts in flow's merges per day and dash's speedometer, as an epic's does; that is accepted. The usage line is plan-hld-command's.

**Done when:**
- tests/pr_removes_story_test.sh, on the in-repo fixture: `finish <hld>` with an epic carrying its `hld:` exits non-zero naming the epic and leaves no `board/finish-<hld>` branch or worktree; an agreed HLD with no `planned:` is refused the same way; a draft HLD is refused; with such an epic only on origin (committed there, not in the main checkout), it exits non-zero and leaves no branch or worktree; with none, it opens one board PR whose diff is `D board/hld/<hld>.md` and the main checkout stays clean. On the external-board fixture, the HLD is deleted in place.
- The existing finish and drop cases pass unchanged.
- `make test` passes.

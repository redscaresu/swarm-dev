---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:story_brief, bin/lib/build.sh:conduct_brief, bin/lib/board.sh:finish_item, drop_story, commands/swarm.md:board-edit rule, docs/reference.md:finish and drop rows, tests/pr_removes_story_test.sh (new)]
easy: false
estimate_lines: 220
---

# The epic's last story PR deletes the epic too, finish and drop go through a board PR, conductors edit stories only through board PRs

Builds on the split: story_brief and conduct_brief in bin/lib/build.sh, finish_item and drop_story in bin/lib/board.sh, board_pr in bin/lib/lifecycle.sh. story_brief already has an in-repo builder delete its story and an external-board builder leave it (bin/swarm.sh:2347-2354; the epic's 2330-2333 is stale). Add: when every other story of the builder's epic is gone or carries after:, the brief also has it delete board/epics/<epic>.md. Of the commands that change a tracked board file (`rm`, `> "${f}.tmp"` and `sed -i` on BOARD paths), the field writes are board-state-out-of-git's and the escalated block escalated-block-out-of-git's; this story routes the deletions. finish_item (:3462-3472), and drop_story through it (:3514-3526), delete through board_pr start/open on an in-repo board and print the PR URL and the `swarm.sh merge --board <url>` that lands it (the lead runs it, or hands it to the user with merge = human). They never touch the main checkout. On an external board they delete in place, as now. conduct_brief and commands/swarm.md say a conductor's scope or body edit to a story goes through board-pr, as the lead's do.

**Done when:**
- tests/pr_removes_story_test.sh: a one-off's brief deletes only its story; an epic story's brief with another open story leaves the epic, and with none (or only an after: story) deletes it too; an external-board story's brief deletes nothing.
- The same test: finish, and drop on an escalated story, on an in-repo fixture board each leave the main checkout's `git status --porcelain` empty, open a board PR (gh stub) and print the merge --board line; on an external board finish deletes the file.
- conduct_brief's text and commands/swarm.md name board-pr for story edits (grep in the test).

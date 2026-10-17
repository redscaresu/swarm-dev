---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/board.sh:set_status, set_fm, get_fm, fm, unblock, pr_stories, money_walk, mark_review, bin/lib/build.sh:build_story, bin/lib/build.sh:start_conductor, bin/lib/agents.sh:story_rows, bin/lib/reports.sh:outcomes_report story reads, docs/reference.md:§ Building board state paragraph, tests/board_state_test.sh (new), tests/board_pr_test.sh, tests/close_test.sh:attempts checks, tests/stacked_test.sh:status checks, tests/wait_lead_test.sh:held_for checks, tests/next_test.sh:status write cases, tests/backlog_test.sh:status checks, tests/review_test.sh:review and held_by checks]
risk: high
easy: false
estimate_lines: 260
---

# Front-matter fields swarm.sh writes live in .swarm/state, and every reader goes through one overlay

Builds on the split: set_status, set_fm, get_fm, fm, unblock, pr_stories, money_walk and mark_review in bin/lib/board.sh. risk high because the costs: money hold finds a PR's story through prs:, and the kind: lead refusal guards escalated stories. set_status and set_fm (bin/swarm.sh:3545,3561) write SET_FM_KEYS (attempts kind escalated_from held_for held_by status prs, :3557) to .swarm/state/board/stories/<slug> or .swarm/state/board/epics/<slug> as `key: value` lines, never to the tracked file. unblock (:3435-3456) writes status there and stops its sed -i. start_conductor's epic active (:3052-3054) goes the same way. fm and get_fm read a key from the state file first and the front matter second, and every other reader goes through them: build_story's ready check and its kind read (:2446-2450), unblock's grep, pr_stories and money_walk (:3274-3300), story_rows (:1745), and outcomes' kind and escalated_from reads (:1257-1258), which read state first and the story in git second. A tracked value with no state entry still reads, so existing boards keep working. The escalated block is escalated-block-out-of-git's, the reconcile cleanup reconcile-drops-backup's, and dash's python readers board-state-dash-readers'. Tests that assert a write in a story file read the state file instead.

**Done when:**
- tests/board_state_test.sh: `swarm.sh review <slug> <url>` on a fixture repo leaves `git status --porcelain` empty, while `next` and `status` show the story in review.
- The same test: after lead_block on a code story, `swarm.sh story <slug>` refuses it as kind: lead, although the tracked file still says kind: code.
- The same test: a costs: money story whose prs: is only in .swarm/state is still held by `swarm.sh merge` (gh stub).
- The same test: an epic and a story with the same slug keep separate status.
- Every tests/*_test.sh passes.

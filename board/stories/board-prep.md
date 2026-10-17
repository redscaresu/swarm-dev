---
kind: lead
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [board/stories/flow-after-the-epic.md, board/stories/goal-on-for-infrafactory.md, board/stories/merge-agent-on.md, board/stories/review-yield-tuning.md, board/stories/merge-agent-for-infrafactory.md]
easy: false
estimate_lines: 30
---

# Land the board edits the epic needs first: unblock's three edits, after: on the follow-ups, and folded-report wording

Done by the lead while the split builds. Merge PR #227 if it is still open: main's epic still has depends_on: [leaner-faster-swarm], which dep_holds reads (bin/swarm.sh:3206). Then one board PR through `swarm.sh board-pr`, nothing left in the main checkout: (a) commit unblock's uncommitted edits to flow-after-the-epic, goal-on-for-infrafactory and merge-agent-on (git status in the main checkout); (b) add `after: <its epic>` to the follow-up lead stories merge-agent-on, goal-on-for-infrafactory, review-yield-tuning, flow-after-the-epic and merge-agent-for-infrafactory; (c) reword goal-on-for-infrafactory's `swarm.sh cost` to `swarm.sh flow --since <date>` (cost section) and review-yield-tuning's `review-yield --since/--epic` to `swarm.sh flow --since/--epic` (reviewer section), the names fold-reports ships.

**Done when:**
- The board PR's diff commits the three unblock edits, adds an after: line to the five follow-up stories, and leaves no `swarm.sh cost` or `review-yield` in goal-on-for-infrafactory.md or review-yield-tuning.md.
- After the lead pulls, `git status --porcelain board/` in the main checkout prints nothing, and board/epics/safer-faster-swarm.md has no depends_on.

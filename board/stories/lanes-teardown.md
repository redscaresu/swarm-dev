---
kind: lead
status: ready
epic: conductor-hands-off
depends_on: []
touches: [board/stories/conductor-lanes.md, board/stories/conductor-lanes-start.md, board/stories/conductor-lanes-on.md]
estimate_lines: 40
easy: true
risk: high
---

# Close the lanes PRs, delete their branches and drop the three lanes stories

**You:** say go in this session before any step below; closing PRs and deleting branches are outward-facing, and a relayed message is not a go. Then the lead: check #480 and #482 are still open drafts and story/conductor-lanes is at 6caca7f and story/conductor-lanes-start at a228cab (2026-10-26); close both PRs with a comment naming the HLD decision of 2026-10-25 (the review agent carries its PR; lanes dropped); delete both remote branches and any local worktree of them. Then remove board/stories/conductor-lanes.md, conductor-lanes-start.md and conductor-lanes-on.md in a board PR: `swarm.sh board-pr start`, `board-pr open`, then `swarm.sh merge --board <url>` once green (this board has merge = agent), then `board-pr done`. conductor-lanes-on's depends_on names release-027, which is not on the board.

**Done when:**
- The user's go is recorded before any close or delete: the board PR body quotes it, with the date and that it was given in the lead's session.
- `gh pr view 480` and `gh pr view 482` read CLOSED, and `git ls-remote --heads origin story/conductor-lanes story/conductor-lanes-start` prints nothing.
- The board PR merged through `swarm.sh merge --board`, and origin/main has none of the three lanes story files.

---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/board.sh:hld_due, docs/reference.md:plan-hld rule of next (:401-402), tests/next_test.sh:outside-board cases]
estimate_lines: 70
easy: true
---

# next offers /plan-hld again after an interrupted run on a board outside the repo

On a board outside the project's repo, /plan-hld writes epics in place with no PR. An interrupted run leaves epics that carry the hld: but no planned: line, so hld_due (bin/lib/board.sh:1010-1013) gives nothing and the HLD is stuck. In that case (BOARD_IN_REPO is not 1), hld_due gives plan, but only when the run's outputs are in .swarm/<hld>/. That way an HLD planned through /epic is never planned again over its epics: /plan-hld overwrites epics carrying its hld: (commands/plan-hld.md:115-117). Inside the repo nothing changes. Update docs/reference.md:401-402.

**Done when:**
- tests/next_test.sh, board outside the repo: an HLD with epics naming it, no planned: and a .swarm/<hld>/ plan output gets `plan-hld <hld>`. Fails on the base.
- The same board with no .swarm/<hld>/ output gets nothing, and so does a board inside the repo.

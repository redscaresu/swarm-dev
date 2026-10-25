---
kind: code
status: later
depends_on: []
touches: [commands/plan-hld.md, bin/lib/board.sh:hld_due and plan_head, bin/lib/dash_render.py:plan and finish rows, hooks/lead-stop.sh:plan_drafted]
estimate_lines: 200
easy: false
---

# /plan-hld closes the gaps its conductor found

For 0.28 (0.27 retro, 2026-10-25). From conduct-plan-hld's report (2026-10-24). Split this when it is planned, if it runs over one PR.
- dash does not match the plan or finish PR rows, so under `lead = session` the user's finish PR lands in the lead's queue.
- `plan_head` accepts a head `planned:` equal to the value already on the board. An empty `planned: ""` makes plan PRs fall to none.
- HLD names containing `.` or `_` pass `next` but are refused by board-pr, grants and finish.
- A rerun whose empty worktree was removed reruns the whole swarm.
- An HLD with no `## Epics`, or with a section after it, makes the plan PR fall to none silently. It should stop and say why.
- A closed plan PR leaves `.swarm/<hld>/critic.json` behind, which lead-stop's plan_drafted counts as a drafted plan.
- On a board outside the repo, an interrupted run leaves the HLD stuck: hld_due offers neither plan-hld nor hld.
- The plan-hld step in swarm.md reads the main checkout's grants, not origin's.
- `grants()`'s usage text does not name `hld`. merge.sh's `files-status` comment lists only four statuses.

**Done when:**
- A test for each gap fails before the fix and passes after it.
- `make test` passes.

---
kind: code
status: blocked
epic: deferred-700
depends_on: [agent-work-several-prs]
needs: [agent-work-several-prs (its edit of the finish rule paragraph (docs/reference-merging.md § Merging) and of tests/epic_finish_test.sh; which this story edits next (shared touches part))]
touches: [bin/lib/board.sh:lead_held, bin/lib/board.sh:agent_work_left (reopened check, shared with lead_held), tests/epic_finish_test.sh:reopened dependency cases, docs/reference-merging.md:finish rule paragraph (§ Merging, :104-121)]
estimate_lines: 70
easy: true
---

# A story blocked on a reopened story waits on the lead, not an agent

Needs from agent-work-several-prs: the finish rule paragraph in docs/reference-merging.md § Merging and tests/epic_finish_test.sh as it left them; this story edits both again. #700 item 2 (#682 round 2). A ready story that reconcile reopened (last event 'reconcile\tok (reopened)', board.sh:2738) is the lead's: agent_work_left skips it (board.sh:846). lead_held (:886-900) returns false for any open depends_on that is not itself blocked, so a story blocked only on a reopened one counts as agent work and holds the finish: and reported: lines. Make lead_held treat a reopened dependency as the lead's, by the same check agent_work_left uses (one small helper both call). Leave lead_blocked (:807-823) as it is: its only caller (board.sh:2156) prints 'which no agent builds', which would be false for a reopened story. The test seam is tests/epic_finish_test.sh:149-156 (ev reconcile s3 - "ok (reopened)"). lead-woken's stuck_lines and reported_lines need no change: reported_lines takes its count from agent_work_left (survey). Prove the new case fails on a worktree copy with the change reverted. Line numbers in this story were read at de5fa7a5; main has moved since (board.sh cites by about 47 lines, lead_held is now near :933, review_agent_owns near :954): find each by its function name.

**Done when:**
- tests/epic_finish_test.sh: a blocked story whose only open depends_on is a reopened ready story does not hold the epic's finish: line; one blocked on a plain ready story still does
- The reopened-dependency case goes red with the reopened check taken out of lead_held, shown on a worktree copy and quoted in the PR
- docs/reference-merging.md § Merging says a story blocked on a reopened story waits on you
- scripts/select-tests.sh --run passes

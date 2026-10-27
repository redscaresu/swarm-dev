---
kind: code
status: blocked
epic: conductor-hands-off
depends_on: [conduct-brief-hands-off, story-merge-notes-conductor, handover-notes-conductor, lead-blocked-not-agent, owner-merge-handoff, close-review-after-merge]
needs: [conduct-brief-hands-off: the rewritten conduct_merge_rule in bin/lib/build.sh, story-merge-notes-conductor: conductor_note and the story-merge note (bin/lib/merge.sh), handover-notes-conductor: the handover note from mark_review (bin/lib/board.sh), for the merge = human finish, lead-blocked-not-agent: lead_blocked (bin/lib/board.sh), review-loop's pr-owner-brief: the review agent hands its PR to the user with swarm.sh review under merge = human, review-loop's close-review-after-merge: review-<slug> retired and closed after its merge, so no tab is left, less-noise's guard-forms-brief: order only (both edit bin/lib/build.sh:conduct_brief); the lead adds depends_on once the slug is final]
touches: [bin/lib/board.sh:agent_work_left (new), bin/lib/merge.sh:conductor_note, bin/lib/build.sh:stop_rule, bin/lib/build.sh:conduct_merge_rule report sentence, bin/lib/build.sh:conduct_brief report paragraph, AGENTS.md:conductor build row and conduct bullet, docs/method.md:Build step, docs/reference.md:Building report lines, docs/reference.md:ready-now note paragraph, tests/epic_finish_test.sh (new), tests/next_test.sh:collect after the last merge, tests/epic_briefs_test.sh:report rules]
estimate_lines: 260
easy: false
---

# The conductor reports only when no agent work is left, and ends the epic at its last merge

Uses conduct-brief-hands-off's rewritten conduct_merge_rule, the merge and handover notes (conductor_note) and lead-blocked-not-agent's lead_blocked. The report is the lead's only finish sign (next_step, bin/lib/board.sh:244; conduct_ready, merge.sh:453-470), so a conductor that reports while a review agent still owns a PR drops that PR's escalations. Code: agent_work_left <epic> (new), true while a story of the epic is ready or blocked for an agent (not lead_blocked, not kind: lead), building, or has an open PR not in review (status: review is the user's); a fix-main story the conductor started counts. conductor_note adds `finish: epic <e> has no agent work left` when it is false after the merge or handover. Brief: rewrite stop_rule (build.sh:29-38), the report sentence in conduct_merge_rule (:186-188) and conduct_brief's report paragraph (:973-979): never write the report while agent work is left; on a `finish:` note, close any review-<slug> of yours still listed, then write the report; a lead-blocked story is listed for the user and holds nothing. next_step keeps the report as its finish sign: no change there. Docs: AGENTS.md:64 and :72, docs/method.md's Build step (:19-32), docs/reference.md § Building's report lines and the ready-now note paragraph. Less-noise's guard-forms-brief also edits conduct_brief: this story merges after it. Less-noise's draft has no docs/method.md story, so the method.md order the first plan named is moot.

**Done when:**
- tests/epic_finish_test.sh (new), gh and herdr stubbed, conduct-e listed: merging s1 while s2 of e has an open PR not in review leaves a note with no `finish:` line (the hold). Fails if completion ignores open PRs.
- The same test: merging e's last agent-owned story gives `finish: epic e has no agent work left`; then, with the report written, `swarm.sh next` prints `collect conduct-e` (a tests/next_test.sh case for board.sh:244), and herdr's stub lists no review-<slug> pane of e.
- The same test, merge = human: `swarm.sh review <last story> <url>` gives the `finish:` note once every agent-owned story is in review.
- The same test: the final merge with a story blocked on a kind: lead parent still on the board gives the `finish:` note. Fails if a lead-blocked story counts as agent work.
- tests/epic_briefs_test.sh: the epic brief under both merge modes and the backlog brief never report while agent work is left, act on `finish:` by closing any review-<slug> left and then reporting, and list a lead-blocked story for the user; the old `Write your report only when no story of this epic that is yours to start is ready and none is running` sentence is gone.
- AGENTS.md:64 and :72 say the conductor starts builds and review agents and ends the epic, and never reviews or merges.

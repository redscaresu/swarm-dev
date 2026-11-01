---
kind: code
status: ready
epic: review-follows-head
depends_on: []
touches: [bin/lib/build.sh:review_next (moved-head case), bin/lib/board.sh:review_heads moved-head refusal message, bin/swarm.sh:review-agent --next usage line, docs/reference-building.md:review-agent --next row (Commands), tests/review_agent_test.sh:--next block (n1 cases), tests/review_agent_test.sh:h2 review --head refusal check]
estimate_lines: 140
easy: false
---

# review-agent --next reviews a moved head again in the same round

When no findings went out since the round started, review_next (bin/lib/build.sh:962-996) refuses today. On round 1 it says 'there is no next round' (:979-982). On a later round it says 'round N has started already' (:984-987). Add one case. If this build has an ok review-agent start (review_rounds' started > 0), no findings round has come since (round == started), and the PR's head (review_at_head) is not the head in .swarm/reviews/<slug>.head, then --next follows the new head. It runs every check it runs today (own pane, board name, herdr list, review_at_head's clean worktree at the PR's head, base_for). It then moves the findings file to .prev and writes the new head to .head. It prints the same round again, naming the new head and the head it moved from, then review_round_line N and the dropped-lines command for the new head. The round count is kept and no event changes: main's review-agent:next line (bin/swarm.sh:1134-1137) logs `ok (round N)` with the same N. review_rounds (build.sh:855-880), outcomes_join's round_starts (bin/lib/outcomes_join.py:225) and no_review_events (bin/lib/lifecycle.sh:3753) already read that line as a round started in the same session. With the head unchanged, both refusals stay. Change review --head's moved-head refusal (bin/lib/board.sh:2589, in review_heads), which says 'after a pass, a new swarm.sh review-agent', to name --next for a head that moved after a pass too, and update its pin at tests/review_agent_test.sh:891. Update bin/swarm.sh:53 and the review-agent --next row (docs/reference-building.md:1098). Follows within a round are not capped: a follow costs one review of the new head, the same as the restart it replaces, and reviews-restarted-row counts what is left.

**Done when:**
- tests/review_agent_test.sh --next block: review-n1 starts on H1 and no findings tell follows. After the worktree and gh's head move to H2, --next from review-n1's pane exits 0 and prints 'Review round 1 of story n1' naming H2. It leaves H2 in .swarm/reviews/n1.head and the old findings file at n1.md.prev. With the new case removed in a copy of the worktree, this check fails; the PR pastes the FAIL line.
- After one findings tell and one --next (round 2 started), a head that moves during round 2 gets round 2 again, not round 3, and events.tsv's new review-agent:next line is `ok (round 2)` with round=2.
- With the PR's head still the one in .head, the existing 'there is no next round' and 'round 2 of n1 has started already' checks (tests/review_agent_test.sh:543-544, 575-576) still pass and change no file under .swarm/reviews.
- A moved head with the worktree behind the PR's head, or with uncommitted changes, is refused as review_at_head refuses it, and no file under .swarm/reviews changes; a check each.
- review --head's moved-head refusal names `review-agent --next` for a head that moved after a pass, and the check at tests/review_agent_test.sh:891 pins the new text.
- Both same-round follow cases print the round's instructions and the dropped-lines command pinned to H2.

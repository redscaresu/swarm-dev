---
kind: code
status: blocked
epic: conductor-hands-off
depends_on: [conduct-brief-hands-off, conductor-report-hold]
needs: [conduct-brief-hands-off: review_rule, review_handoff and review_brief in bin/lib/build.sh as it leaves them; conductor-report-hold: order only, both edit bin/lib/build.sh]
touches: [bin/lib/build.sh:review_rule, bin/lib/build.sh:review_handoff, bin/lib/build.sh:review_brief, bin/lib/lifecycle.sh:wait --lead review stop line, docs/reference.md:review agent hand-off, tests/review_handoff_gaps_test.sh (new)]
estimate_lines: 200
easy: false
---

# Every way a review agent stops reaches an owner, and a new head is never left unreviewed

Deferred by the lead from conduct-brief-hands-off's (#666) review rounds 3 and 4 under the round cap (2026-10-28). That PR made the review agent own the hand-off and the conductor hands-off. These paths still drop a PR or start a needless review:

1. A builder pushes while the old review agent is still in its session (mid-round, or after a pass while `swarm.sh merge` runs). watch prints `checks finished` for that head once, the conductor's start is refused, and the head waits for `queued:` (30 minutes by default). Fix: the review agent sends a `review-<slug> stopped on <sha>` note when it stops on a moved head (`head moved:`), and the conductor restarts on that note.
2. A second refusal on the same head with the builder idle is read as GitHub's base merge with no check. Fix: check events.tsv for `merge <slug> base-merged <sha>` on that head; otherwise tell the builder to pull the PR's head and start the review again.
3. A `checks finished` restart after a pass on the same head starts a second review that can send findings to a PR already merging. Fix: no restart for a head whose findings file is a pass.
4. A stacked story that `swarm.sh review` holds (`held: <slug> waits for <p> to merge`): review_rule has no case, so the conductor nudges an idle builder and restarts a review in a loop. Fix: a held stop note means wait for <p>'s merge.
5. A fix-main story's stop note goes to conduct-backlog, not the epic conductor running it. Fix: send it to the conductor that started the build.
6. When the stop note's tell fails (no conductor running), the reply says "the lead takes it", but nothing reaches the lead. Fix: a `wait --lead` line for a review agent's `stopped:` file with no conductor running.

**Done when:**
- tests/review_handoff_gaps_test.sh (new) covers each of the six paths above and fails when its fix is removed (FAIL lines in the PR).
- docs/reference.md's review agent hand-off section describes each path.

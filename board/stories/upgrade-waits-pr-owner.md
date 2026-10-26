---
kind: code
status: blocked
epic: conductor-hands-off
depends_on: [owner-merge-handoff, next-review-round]
needs: [review-loop's pr-owner-brief: the review agent tells its builder and merges or hands over its PR (bin/lib/build.sh:review_brief), review-loop's next-review-round: the review agent loops in its own session, so it is a long-lived Claude agent upgrade must wait for]
touches: [bin/lib/lifecycle.sh:upgrade_round, bin/lib/lifecycle.sh:upgrade_hold, bin/lib/lifecycle.sh:upgrade_held_why, bin/swarm.sh:upgrade usage line, docs/reference.md:upgrade paragraph, README.md:upgrade lines, tests/upgrade_test.sh:review agent cases]
estimate_lines: 160
easy: false
---

# swarm.sh upgrade holds a builder while the review agent that owns its PR is busy

upgrade_want already lists each story's review-<slug> (bin/lib/lifecycle.sh:3446-3459). What waits only on the conductor is the hold: upgrade_round (:3169-3212) holds an epic's builders on its conductor's handover through upgrade_hold (:3342-3349), because the conductor told and merged for them. After review-loop the story's review agent does that and lives across rounds in its own session. Hold a builder's restart while its story's Claude review agent (agent_name of review-<slug>, exact) is listed, on the old version and not idle (upgrade_state); restart the review agent itself only when idle, as any agent. A review agent still busy at the end of the wait is left and named, and its builder is left with that reason (upgrade_held_why). A codex review agent holds nothing, as today. Document it in docs/reference.md's upgrade paragraph (:2177), README.md's upgrade lines (:145-156) and the upgrade usage line (bin/swarm.sh:27).

**Done when:**
- tests/upgrade_test.sh: with a Claude review-b1 busy and builder b1 idle, the round restarts neither and upgrade keeps waiting; once review-b1 reads idle, both are restarted. Fails on today's code, which restarts b1 while review-b1 is busy.
- tests/upgrade_test.sh: a review-b1 still busy past SWARM_UPGRADE_WAIT_MS is named as left, and b1 is left with a reason naming review-b1.
- tests/upgrade_test.sh: the existing codex review-b1 case and the conductor handover cases assert what they did before.

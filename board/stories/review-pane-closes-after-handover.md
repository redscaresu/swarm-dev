---
kind: code
status: blocked
epic: machine-usable
depends_on: [review-pane-closes-after-merge]
needs: [review-pane-closes-after-merge (close_when_idle <name> <pane> in bin/lib/lifecycle.sh; the detached wait-then-close.)]
touches: [bin/lib/board.sh:mark_review (handover tail), tests/review_test.sh:handover cases, docs/reference-merging.md:Merging (handover closes review-<slug>)]
estimate_lines: 80
easy: false
---

# A review pane closes itself after it hands a PR to the user

Uses close_when_idle from review-pane-closes-after-merge. With merge = human and no HLD merge grant, the review agent hands its PR over with `swarm.sh review <slug> <url>` (mark_review, bin/lib/board.sh:2519; note at 2593-2606) and nothing closes review-<slug> until the user merges, maybe days later. When that command runs from review-<slug>'s own pane in that mode, it calls close_when_idle for it. From any other pane (lead, conductor) it closes nothing.

**Done when:**
- tests/review_test.sh: `swarm.sh review a <url>` from review-a's pane with merge = human gets `pane close <its pane>` from fake herdr after the command exits and the agent reads idle; it goes red with the call removed.
- The same command from another pane, or with merge = agent, closes no pane.
- After that close, `swarm.sh wait --lead` prints no no-review: line for story a.
- docs/reference-merging.md says the review pane closes after its handover.

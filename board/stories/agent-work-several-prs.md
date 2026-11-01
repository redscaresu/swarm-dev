---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/board.sh:review_agent_owns, tests/epic_finish_test.sh:several-PR review cases, docs/reference-merging.md:finish rule paragraph (§ Merging, :104-121), commands/swarm.md:finish count sentence (413)]
estimate_lines: 60
easy: true
---

# A story in review with several PRs is the lead's, kept or not

#700 item 1 (#682 round 2). review_agent_owns (bin/lib/board.sh:902-912) applies the one-PR rule (story_prs | wc -w -eq 1) only to a story a close kept (kept:). Under merge = agent or an HLD merge grant, a story put in review by hand with several PRs falls to the second branch, counts in agent_work_left (:841-850) and holds back the conductor's finish: line and wait --lead's reported: count (lifecycle.sh:3440-3465). Apply the PR-count rule to every story in review, as review_rule says a several-PR story is the lead's. Update the review_agent_owns comment and the finish rule's list in docs/reference-merging.md § Merging (':118 a kept story with several PRs'). Add cases to tests/epic_finish_test.sh beside the kept: case (:157-163). Prove the new case fails on a worktree copy with the change reverted (AGENTS.md mutation rule). Line numbers in this story were read at de5fa7a5; main has moved since (board.sh cites by about 47 lines, lead_held is now near :933, review_agent_owns near :954): find each by its function name. Correction: review_rule (bin/lib/build.sh:104-105) gives a several-PR story to the lead only when it is kept:; update review_rule too, so the brief and the count agree for every story in review.

**Done when:**
- tests/epic_finish_test.sh has a case under merge = agent: a story in review, not kept, with two PRs, and the epic's merge note ends with its finish: line; with one PR the finish: line is still held
- That two-PR case goes red when the PR-count check is taken off the non-kept branch, shown on a worktree copy and quoted in the PR
- docs/reference-merging.md § Merging says a story in review with several PRs is the lead's, kept or not
- commands/swarm.md's line on several-PR stories says it for every story in review, kept or not.
- scripts/select-tests.sh --run passes
- The conductor brief's review_rule names a several-PR story as the lead's, kept or not; a has() check.

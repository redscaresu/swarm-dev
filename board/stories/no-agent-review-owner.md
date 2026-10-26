---
kind: code
status: blocked
epic: review-loop
depends_on: [next-review-round]
needs: [next-review-round: the `review-agent:next <slug> ok (round <n>)` event bin/swarm.sh:main logs]
touches: [bin/lib/lifecycle.sh:no_review_events, bin/lib/lifecycle.sh:no_agent_lines, tests/no_agent_test.sh:review owner cases, tests/wait_lead_test.sh:review owner cases]
estimate_lines: 180
easy: false
---

# The no-agent alert reads the review agent as the PR's owner

Uses next-review-round's `review-agent:next <slug> ok (round <n>)` event (bin/swarm.sh:main). no_review_events (lifecycle.sh:2253-2312) counts a round as under way once an ok tell:findings follows the last review-agent line. With rounds in one session, a review-agent:next line starts the new round. no_agent_lines skips a story in review unless merge = agent (lifecycle.sh:2475). Under merge = human, a story in review whose HLD grants merge waits on its review agent's merge. If that agent went after `swarm.sh review` and before the merge, the story needs the lead. An ordinary human handoff (no grant) stays silent. Read the grant within the poll's gh budget, once per story in review.

**Done when:**
- tests/no_agent_test.sh: a review agent that started, told findings from its own pane, ran --next (round 2), then went with the PR open gives a no-review: line. One gone after an ok tell:findings with no --next since (the builder fixing) gives none.
- Under merge = human, a story in review whose HLD grants merge, with its review agent gone and its PR open, gives a line that reaches wait --lead (tests/wait_lead_test.sh). The same story with no grant gives none.
- The existing no_agent_test.sh and wait_lead_test.sh cases pass.

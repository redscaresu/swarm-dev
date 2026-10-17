---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [escalate-ladder-step-up]
touches: [bin/lib/lifecycle.sh:close_agent, bin/lib/agents.sh:wait_agent, bin/lib/agents.sh:tell_agent, bin/lib/merge.sh:watch_prs, bin/lib/build.sh:conduct_brief, tests/escalate_triggers_test.sh (new)]
easy: false
estimate_lines: 200
---

# swarm.sh detects the four ladder triggers itself and steps the build up

Needs escalate-ladder-step-up's `swarm.sh step-up`. With escalate_ladder set, swarm.sh calls step-up itself: no-pr when close_agent closes a ready story's builder with no PR; stalled when wait --stall finds the builder stalled (wait_agent); findings-3 when tell_agent sends a builder its third tell:findings; ci-red-2 when watch_prs sees ci_gate red on two of the story's own heads. conduct_brief gets one line saying swarm.sh steps builds up on these, so the conductor does not close or retry them. With escalate_ladder empty, nothing changes.

**Done when:**
- tests/escalate_triggers_test.sh: with the ladder on, each stubbed condition (a no-PR close, a stall, a third findings tell, two red heads) runs step-up for that trigger with no manual call; with the ladder off, none does.
- conduct_brief with the ladder on has the step-up line, and with it off does not (grep).

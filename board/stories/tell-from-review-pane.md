---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/agents.sh:tell_agent, bin/lib/build.sh:findings_goal, tests/escalate_triggers_test.sh:review pane findings cases, tests/ladder_top_rung_test.sh:review pane cases]
estimate_lines: 120
easy: false
---

# tell from a review agent counts rounds, steps up and holds as from the conductor

tell_agent (bin/lib/agents.sh:1619-1680) has no caller logic, so a review pane can call it. Pin with tests that a review pane's findings tells count (findings_told) and fire the step-up at step_up_findings (ladder_step) and the top-rung hold at top_rung_rounds (top_rung_hold). The text the builder gets says who sent it. From review-<slug>'s pane, it starts 'From the review agent:' and the /goal (findings_goal, build.sh:8-13) names the review agent's findings. From any other pane it keeps 'From the conductor:' (next_test.sh:1182-1215 pins it).

**Done when:**
- tests/escalate_triggers_test.sh: with HERDR_PANE_ID on review-<slug>'s pane, findings tells 1 and 2 are logged tell:findings ok, and the step_up_findings-th steps the build up (escalate line) and tell exits non-zero with its step-up message.
- tests/ladder_top_rung_test.sh: on the top rung the top_rung_rounds-th findings tell from the review pane holds the story (held_for: top-rung).
- The sent file starts 'From the review agent:' from the review pane and 'From the conductor:' from any other; tests/next_test.sh passes.

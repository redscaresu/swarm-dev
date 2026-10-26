---
kind: code
status: blocked
epic: review-loop
depends_on: [wording-recheck, owner-findings-rounds]
needs: [wording-recheck: `review-agent --recheck` (bin/lib/build.sh:review_agent), owner-findings-rounds: the triage step in bin/lib/build.sh:review_brief]
touches: [bin/lib/build.sh:review_brief, tests/review_agent_test.sh:wording route case]
estimate_lines: 70
easy: true
---

# Wording-only findings go to the builder as a nudge and are rechecked on their diff

Uses wording-recheck's `review-agent --recheck` and owner-findings-rounds' triage in bin/lib/build.sh:review_brief. Add to review_brief: when every finding to fix is wording (a comment, doc or error-text line that misstates the code), send them with `swarm.sh tell <slug> nudge` naming each file:line. A nudge is not a round, so the ladder does not move. On the new head, run --recheck with the old head and those points; when it refuses, run --next and a full round. v0.28.0 retro: #560 spent a full round on two wording points.

**Done when:**
- A test runs the brief's nudge and --recheck commands as the brief writes them, from a stand-in review pane, against a fixture: the nudge is logged tell:nudge ok, and --recheck passes on a wording-only diff.
- The same --recheck command on a diff that changes code is refused, and the brief's next step on that refusal is --next.
- tests/review_agent_test.sh pins the wording route in the brief.

---
kind: lead
status: ready
epic: goal-for-builders
depends_on: [goal-for-builders-release]
touches: []
---

# Measure goal on infrafactory against the goal-off baseline, and the lead decides whether it stays on

infrafactory has run `goal = 5` since 2026-10-16. The user handed the keep-or-remove call to the lead on 2026-10-17. For one infrafactory epic's window of .swarm/events.tsv and agents.tsv, the lead posts on this story:
- the `nudge` and `tell:nudge` counts;
- the tell:findings and tell:resume counts;
- each builder close with its cause, and any builder that stopped short with no cause;
- `swarm.sh cost` for the window, with the judge's tokens or a note that they are missing.

It sets these beside the goal-off baseline that infrafactory-epic-on-agent-state posted (its last version in git).

**Decision rule.** Goal stays on when all of these hold:
- the window has fewer nudges than the baseline;
- no builder stopped short with no cause;
- the judge's cost is under 5% of the window's build cost.

Otherwise the lead removes the `goal` line. Either way it tells the user the result and why.

**Done when:**
- The window's counts are posted on this story beside the baseline's.
- Every close of a ready story's builder is close:<cause>. Any exception is listed by slug, and a story is filed for it.
- `swarm.sh cost` for the window is posted, with the judge's tokens or the line that they are missing.
- The lead's decision is recorded on the story with the rule's numbers, and infrafactory's `swarm.sh config goal` matches it.

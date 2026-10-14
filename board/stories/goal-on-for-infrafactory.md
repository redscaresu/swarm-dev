---
kind: lead
status: blocked
blocked_by: [goal-spike, goal-for-builders-release]
epic: goal-for-builders
depends_on: [goal-spike, goal-for-builders-release]
touches: []
---

# Turn goal on for one infrafactory epic, set its nudges and causes beside the goal-off baseline, and you decide whether it stays on

After the release merges. **You:** run `claude plugin update swarm-dev@swarm-dev`, restart Claude Code and say go. The lead adds `goal = <the bound the spike named>` to infrafactory's .claude/swarm/config (no agent edits it) and checks `swarm.sh config goal` there. **You:** run /swarm on infrafactory for one epic. The lead then posts on this story, for that epic's window of infrafactory's .swarm/events.tsv and agents.tsv: the `nudge` and `tell:nudge` counts, the tell:findings and tell:resume counts, each builder close with its cause, any builder that stopped short with no cause, and `swarm.sh cost` for the window with the judge's tokens or a note that they are missing (per the spike). It sets these beside the goal-off baseline that infrafactory-epic-on-agent-state posted (its last version in git). **You:** decide whether goal stays on; the lead keeps or removes the line to match.

**Done when:**
- The window's counts are posted on this story beside the baseline's.
- The window has zero `nudge` and zero `tell:nudge` lines, and every close of a ready story's builder is close:<cause>; otherwise each exception is listed by slug and a story is filed for it.
- `swarm.sh cost` for the window is posted, with the judge's tokens or the line that they are missing.
- The user's decision is recorded on the story, and infrafactory's `swarm.sh config goal` matches it.

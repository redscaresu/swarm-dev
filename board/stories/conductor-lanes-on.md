---
kind: lead
status: blocked
depends_on: [conductor-lanes-start, release-027]
touches: [.claude/swarm/config]
estimate_lines: 3
easy: true
---

# swarm-dev runs three conductor lanes and steps up on the 2nd findings round

Once 0.27 ships, the lead changes two settings in swarm-dev's own .claude/swarm/config, in one PR of their own. Merging the code changed nothing until this lands. The lead merges it (merge = agent).
- `conductor_lanes = 3`. The user asked for several conductors on 2026-10-24.
- `step_up_findings = 2`. The user decided on 2026-10-25 that if a 2nd review still finds things worth fixing, the build moves up the ladder at once instead of getting a 3rd round. `top_rung_rounds` stays at 2: a 2nd round of real findings on fable goes to the lead. A round with nothing fixed is still a pass.

After one epic, the lead posts flow's review_loops and holds figures, before and after, in this file.

**Done when:**
- On main, `swarm.sh config conductor_lanes` prints 3 and `swarm.sh config step_up_findings` prints 2.
- After the next epic, its lane conductors, its step-ups and the flow figures are posted here.

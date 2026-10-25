---
kind: lead
status: later
depends_on: [conductor-lanes-start, release-027]
touches: [.claude/swarm/config]
estimate_lines: 2
easy: true
---

# swarm-dev runs three conductor lanes

**Out of 0.27 (user, 2026-10-25):** conductor lanes go to the 0.28 HLD as a design question. #480 drew real multi-lane gaps in five review rounds on fable without converging. Branches kept: story/conductor-lanes (#480, draft, 6caca7f) and story/conductor-lanes-start (#482, draft, a228cab, reviewed clean on 2026-10-25 03:22). Re-plan from the HLD; do not restart these builds as they stand.


Once conductor-lanes and conductor-lanes-start ship, the lead sets `conductor_lanes = 3` in swarm-dev's own .claude/swarm/config, in a PR of its own, so that merging the code changes nothing until this lands. The user asked for several conductors on 2026-10-24, so the lead merges it (merge = agent). After one epic, the lead posts flow's review_loops and holds figures before and after, in this file.

**Done when:**
- `swarm.sh config conductor_lanes` prints 3 on main.
- After the next epic, its lane conductors and the flow figures are posted here.

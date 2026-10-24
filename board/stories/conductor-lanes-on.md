---
kind: lead
status: blocked
depends_on: [conductor-lanes-start, release-027]
touches: [.claude/swarm/config]
estimate_lines: 2
easy: true
---

# swarm-dev runs three conductor lanes

Once conductor-lanes and conductor-lanes-start ship, the lead sets `conductor_lanes = 3` in swarm-dev's own .claude/swarm/config, in a PR of its own, so that merging the code changes nothing until this lands. The user asked for several conductors on 2026-10-24, so the lead merges it (merge = agent). After one epic, the lead posts flow's review_loops and holds figures before and after, in this file.

**Done when:**
- `swarm.sh config conductor_lanes` prints 3 on main.
- After the next epic, its lane conductors and the flow figures are posted here.

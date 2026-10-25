---
kind: lead
status: later
epic: safer-faster-swarm
blocked_by: [merge-admin]
depends_on: [merge-admin]
touches: [infrafactory: .claude/swarm/config]
---

# infrafactory sets merge_admin = on

**Parked (2026-10-25):** the 0.28 HLD rules infrafactory out. Start it again after 0.28.

Once merge-admin is released and installed, set `merge_admin = on` in infrafactory's
`.claude/swarm/config` with a comment: the ruleset requires an approving review the swarm cannot
give, and the lead merges with `--admin` under the same checks anyway. One infrafactory PR the
lead merges. **You:** none.

**Done when:**
- `swarm.sh config merge_admin` in infrafactory prints `on`.
- The next infrafactory conductor run merges a PR itself (its report is quoted here), which also completes merge-agent-for-infrafactory's last item.

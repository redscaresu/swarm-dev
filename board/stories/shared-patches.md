---
kind: lead
status: later
epic: helpers-shared
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: cut a v0.32.x patch to prerelease as this epic's ports merge, and roll back by the ref

Shared step L2 (HLD:313,433-436). Needs no other story.
- Lead: once this epic's port PRs have merged, cut a v0.32.x patch through /swarm-dev:swarm's release arm and `swarm.sh merge --release`. The patch gate passes a port: true story whose changed tests/ files its touches list (docs/reference-merging.md:1097).
- Lead: after each patch, and before and after each stable move, check that stable and prerelease point at their expected tags (`git ls-remote origin stable prerelease`). The lead and every agent share one gh login, so the ruleset cannot tell their pushes apart.
- Lead: if the swarm stalls on a port, revert or fix it on main, move prerelease back and restart the sessions.
Every stage-2 epic carries this step; the lead may keep one story for all of them.

**Done when:**
- Every port PR of this epic is in a v0.32.x tag that prerelease pointed at. The ref check after the last patch is quoted in this story's file.

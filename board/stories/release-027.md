---
kind: lead
status: blocked
depends_on: [retro-027]
touches: [.claude-plugin/plugin.json, README.md, AGENTS.md, docs]
estimate_lines: 0
easy: false
---

# Release 0.27.0

Cut once retro-027 is done. It ships the HLD layer (epics hld-command, hld-grants, plan-hld, epic-guard and hld-docs) and every 0.27 story filed on 2026-10-24: lean plan verify, holds, review rounds and loop metrics, review-loop-trim, the ladder fixes, test-run-log, the grant safety fixes and close-exact-tab.

- A docs PR that updates AGENTS.md, README, docs and the release notes (user, 2026-10-21), including an upgrade note: set `planned:` by hand on any HLD decomposed before 0.27.
- A version-bump PR, then `merge --release`. That updates the plugin and upgrades every agent.
- Then ask the user to restart the lead session.
- Conductor lanes are not in 0.27: they go to the 0.28 HLD.

**Done when:**
- Tag v0.27.0 and its GitHub release exist, and `swarm.sh upgrade` reports every agent on 0.27.0.

---
kind: lead
status: ready
depends_on: []
touches: []
---

# Lead: cut v0.28.0, and switch on the next stage

The 0.28 HLD ships in staged releases (board/hld/2026-10-25-swarm-dev-0-28.md, Rollout § Stages). The plan PR could only add epics, so each stage's release is this lead story (stage-gating's constraints). Start it when `swarm.sh next` prints `release v0.28.0`.

1. **Docs.** List the behaviour changes since v0.27.2 (`git log v0.27.2..origin/main`). Each story updated its own docs; check README.md, AGENTS.md, docs/ and commands/ cover every change, and land a docs PR for any gap.
2. **The release PR**, through /swarm-dev:swarm's release arm: bump only `.claude-plugin/plugin.json` to 0.28.0, list the PRs merged since v0.27.2, the behaviour changes every project gets on upgrade, and the infrafactory build they were tried on (or none). No HLD grants `release`, so the user merges it.
3. **You:** merge the release PR, then restart the lead session (`/exit`, then `claude --continue`) so it runs v0.28.0. The lead learns it is done when `swarm.sh version` prints 0.28.0.
4. **The next stage.** Run the v0.28.0 retro (retro-v0-28-0) first, so its fixes are in the v0.29.0 epics before they are planned. Then, once v0.28.0 is tagged, `next` prints `stage v0.29.0`: follow its arm to set that stage's draft epics active (a board PR under the HLD's `epics` grant).
5. Put `stall_minutes` in swarm-dev's local .claude/swarm/config back to the default 30 (the lead raised it to 60 on 2026-10-26 while stall-counts-test-runs was unreleased), and run the post-release lead checks: ppid-check-after-review and unsent-resend-real-pane.

**Done when:**
- The tag v0.28.0 exists, `gh release view v0.28.0` shows it, and `swarm.sh version` in the lead session prints 0.28.0.
- The v0.29.0 stage's epics are active on main.

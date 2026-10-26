---
kind: lead
status: later
depends_on: []
touches: []
---

# Lead: cut v0.31.0, and switch on the next stage

The 0.28 HLD ships in staged releases (board/hld/2026-10-25-swarm-dev-0-28.md, Rollout § Stages). The plan PR could only add epics, so each stage's release is this lead story (stage-gating's constraints). Start it when `swarm.sh next` prints `release v0.31.0`.

1. **Docs.** List the behaviour changes since v0.30.0 (`git log v0.30.0..origin/main`). Each story updated its own docs; check README.md, AGENTS.md, docs/ and commands/ cover every change, and land a docs PR for any gap.
2. **The release PR**, through /swarm-dev:swarm's release arm: bump only `.claude-plugin/plugin.json` to 0.31.0, list the PRs merged since v0.30.0, the behaviour changes every project gets on upgrade, and the infrafactory build they were tried on (or none). No HLD grants `release`, so the user merges it.
3. **You:** merge the release PR, then restart the lead session (`/exit`, then `claude --continue`) so it runs v0.31.0. The lead learns it is done when `swarm.sh version` prints 0.31.0.
4. **The last stage.** v0.31.0 carries the retro gate; the 0.28 retro runs before it (retro-report).


**Done when:**
- The tag v0.31.0 exists, `gh release view v0.31.0` shows it, and `swarm.sh version` in the lead session prints 0.31.0.


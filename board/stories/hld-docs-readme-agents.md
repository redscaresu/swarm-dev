---
kind: docs
status: blocked
epic: hld-docs
depends_on: [plan-hld-command, plan-pr-grant, epic-guard-merge]
touches: [README.md, AGENTS.md, docs/assets/swarm-flow.workflow.json, docs/assets/swarm-flow-light.png, docs/assets/swarm-flow-dark.png]
estimate_lines: 60
easy: false
---

# README, AGENTS.md and the flow diagram start at /hld

Needs, from each depends_on: the shipped `/hld` and `/plan-hld` commands and the grants' names, as merged on main.

- README.md's quick start and AGENTS.md's three-step run name `/hld` as where a release's worth of work starts.
- AGENTS.md's never-merge rule under `merge = human` names the `merge` and `release` grants as its exception.
- docs/assets/swarm-flow.workflow.json gains the HLD step ahead of the epic step.
- Re-render docs/assets/swarm-flow-light.png and swarm-flow-dark.png from it with archify, the local skill at ~/.claude/skills/archify/archify: `node bin/archify.mjs validate workflow <json>`, then `render workflow <json> <out.html>`, then screenshot only the diagram in light and dark (`?theme=dark`) with Playwright and the installed Chrome, at 1440 px wide like the current PNGs, with no viewer chrome (title bar, toolbar, zoom controls). Render into a scratch directory, never into the skill.
- Prose goes through the humanizer.

**Done when:**
- `grep -n "/hld" README.md AGENTS.md` hits the quick start and the three-step run.
- The workflow JSON parses (`python3 -m json.tool`) and names an HLD step before the epic step.
- Both PNGs show the HLD step and no viewer chrome; the builder opens each and says so in the PR.
- `make test` passes.

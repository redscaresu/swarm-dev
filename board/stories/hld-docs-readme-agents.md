---
kind: docs
status: blocked
epic: hld-docs
depends_on: [plan-hld-command, plan-pr-grant, epic-guard-merge]
touches: [README.md, AGENTS.md, docs/assets/swarm-flow.workflow.json]
estimate_lines: 40
easy: true
---

# README, AGENTS.md and the flow diagram start at /hld

Needs, from each depends_on: the shipped `/hld` and `/plan-hld` commands and the grants' names, as merged on main.

- README.md's quick start and AGENTS.md's three-step run name `/hld` as where a release's worth of work starts.
- AGENTS.md's never-merge rule under `merge = human` names the `merge` and `release` grants as its exception.
- docs/assets/swarm-flow.workflow.json gains the HLD step ahead of the epic step. The PNGs are re-rendered by the lead story hld-diagram-render, not here.
- Prose goes through the humanizer.

**Done when:**
- `grep -n "/hld" README.md AGENTS.md` hits the quick start and the three-step run.
- The workflow JSON parses (`python3 -m json.tool`) and names an HLD step before the epic step.
- `make test` passes.

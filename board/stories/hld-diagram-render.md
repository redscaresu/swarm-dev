---
kind: lead
status: blocked
epic: hld-docs
depends_on: [hld-docs-readme-agents]
touches: [docs/assets/swarm-flow-light.png, docs/assets/swarm-flow-dark.png]
estimate_lines: 0
easy: true
---

# The flow diagram PNGs show the HLD step

Needs, from hld-docs-readme-agents: docs/assets/swarm-flow.workflow.json with the HLD step.

The lead asks the user to re-render the light and dark PNGs from the workflow JSON, then opens one PR with both and merges it.

**You:** run archify on docs/assets/swarm-flow.workflow.json for the light and dark PNGs (archify is on your machine), and tell the lead where they are.

**Done when:**
- Both PNGs on main show the HLD step, checked by opening them.

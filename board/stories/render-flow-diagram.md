---
kind: lead
status: blocked
blocked_by: [docs-refresh-0-14]
depends_on: [docs-refresh-0-14]
touches: [docs/assets/swarm-flow-light.png, docs/assets/swarm-flow-dark.png]
---

# Re-render the flow diagram for v0.14.0

docs-refresh-0-14 updated `docs/assets/swarm-flow.workflow.json` (`swarm.sh init` before `/hld`, and the
`auth` → `/login` stop), but could not render it: Archify (https://github.com/tt-a1i/archify) is not
installed anywhere trusted on this machine, and the agent's permission check rightly refused to run a copy
from another session's scratch folder.

**You:** say whether to install Archify. The lead would clone it at a pinned commit into
`~/.claude/skills/archify`, read its install script before running anything, and render. Or render the two
PNGs yourself from the JSON as before.

The lead then renders `swarm-flow-light.png` and `swarm-flow-dark.png` from the JSON, checks that both show
`swarm.sh init` and the `auth` stop, and opens the PR with both images embedded.

**Done when:** both PNGs on main show `swarm.sh init` and the `auth` stop; release-agent-state then runs.

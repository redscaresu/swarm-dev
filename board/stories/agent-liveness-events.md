---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [api-error-stall]
touches: [bin/lib/agents.sh:record_event callers, bin/lib/dash_render.py:agents, bin/lib/flow_incidents.py, tests/]
---

# Agent stops, API errors and auto-mode denials land in events.tsv

On 2026-10-18 a conductor sat stopped on ECONNRESET for an hour, and a builder spent seven review
rounds on a Done when that auto mode would never let it run. Neither left a trace the swarm reads.
When `wait` or `status` sees an agent's pane end on `API Error:` or a "denied by the Claude Code
auto mode classifier" line, record_event logs `api-error` or `auto-denied` with the agent and the
first line of the message, once per occurrence. dash's agent line shows each agent's minutes since
its pane last changed, and `flow`'s incidents section counts both events per epic.

**Done when:**
- Fixture panes ending on each line give exactly one event each across two `status` runs.
- dash shows `12m` beside a fixture agent whose pane last changed 12 minutes ago, and its agreement assertion passes.

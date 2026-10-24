---
kind: code
status: ready
risk: high
depends_on: []
touches: [bin/lib/lifecycle.sh:close's tab match, tests/close_exact_tab_test.sh (new)]
estimate_lines: 40
easy: true
---

# close never closes another agent's tab

`close` in bin/lib/lifecycle.sh matches a tab on the first 32 characters of its name (conduct-plan-hld report, 2026-10-24). So two names that share their first 32 characters can close each other's tab: two `plan-<hld>` tabs for long HLD names, or a long story slug next to its review agent. Closing the wrong agent loses its work and, for a builder, can count an attempt that never happened.

- `close` matches the exact recorded tab or pane from .swarm/state, never a prefix. If no exact record matches, it refuses and names what it found.

**Done when:**
- tests/close_exact_tab_test.sh: with two recorded agents whose names share their first 32 characters, `close` on one leaves the other's pane open. `close` on a name with no exact record refuses.
- `make test` passes.

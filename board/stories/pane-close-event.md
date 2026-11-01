---
kind: code
status: ready
epic: machine-usable
depends_on: []
touches: [bin/lib/lifecycle.sh:close_pane, bin/lib/lifecycle.sh:tidy_panes, tests/close_test.sh:pane-closed case, tests/agent_state_test.sh:tidy cases, docs/reference-logs.md:Logs and outcomes (pane-closed line), bin/lib/build.sh:unclear review pane close (1240)]
estimate_lines: 80
easy: false
---

# Log a pane-closed event for every pane swarm.sh closes

flow panes needs a close time per review pane, and today only the `close` command logs one: a close inside merge/reconcile (merged_review -> shut_agent -> close_pane) writes no event, and `tidy --yes` logs target '-' (bin/swarm.sh:1111). close_pane (bin/lib/lifecycle.sh:1770-1795) and tidy_panes' close loop (lifecycle.sh:1970-1979) each append one `pane-closed` line per pane they close, its target the agent name, with pane=<id> and agent_fields' slug= and role= (a retired -done name reads the name before, agents.sh:912-927). Match on that slug=, never on a cut name (rules.md rule 10). The review agent's direct `herdr pane close` of an unclear review pane (build.sh:1240) goes through close_pane too, so it logs pane-closed.

**Done when:**
- tests/close_test.sh: `swarm.sh close review-x` writes one pane-closed line with slug=x role=review pane=<its pane>; it goes red with the append removed from close_pane.
- tests/agent_state_test.sh: `tidy --yes` over two retired panes writes two pane-closed lines, one per pane id; a pane herdr could not close writes none.
- docs/reference-logs.md § Logs and outcomes lists the pane-closed line and its fields.

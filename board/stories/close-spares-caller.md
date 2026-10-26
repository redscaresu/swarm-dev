---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/lifecycle.sh:live_agents, tests/close_test.sh:caller pane cases]
estimate_lines: 150
easy: false
risk: high
---

# A tab close never takes the pane running the command

A review agent runs in its story's tab (build.sh:599-600) and may sit idle while its own background swarm.sh tell or merge runs. close_panes falls back to close_tabs <slug> (lifecycle.sh:1517-1518), and close_tab closes a tab whose agents live_agents (lifecycle.sh:1700-1766) reads as idle. So a step-up or reconcile run from that pane can close it. Make live_agents keep the pane in HERDR_PANE_ID, with the reason 'the pane running this command'. This changes every tab close, from tidy and reconcile too, hence risk: high. Keep the change out of close_panes. Merge after less-noise's name-cut story (both edit live_agents).

**Done when:**
- tests/close_test.sh: a step-up run from an idle review-<slug> pane in a backlog story's own tab, whose builder has no tab record (the close_tabs fallback), closes the builder and leaves the review pane and its tab open. With HERDR_PANE_ID unset, the same sweep closes the tab.
- reconcile's close of a merged story's builder, run from that story's idle review pane, leaves the review pane open, for an epic story and a backlog story; a check each.
- tidy --yes and a close from the lead's pane close the same tabs as before; tests/close_exact_tab_test.sh passes.

---
kind: code
status: blocked
epic: review-loop
depends_on: [close-spares-caller]
needs: [close-spares-caller: bin/lib/lifecycle.sh:live_agents keeping the pane in HERDR_PANE_ID]
touches: [bin/lib/board.sh:reconcile merged arm, bin/lib/board.sh:drop_gone_state, tests/reconcile_pull_test.sh:review agent cases]
estimate_lines: 180
easy: false
---

# After a merge from the review pane, review-<slug> is retired, then closed

Uses close-spares-caller's guard in bin/lib/lifecycle.sh:live_agents, so a reconcile run from the review pane never closes it. reconcile closes a merged story's builder (board.sh:1781-1790) but never its review agent, and tidy closes only empty or -done panes (lifecycle.sh:1768-1772). In reconcile's merged arm, close an open review-<slug>. When it is the pane running reconcile, retire it instead (retire_agent, agents.sh:1761), so tidy or the conductor's finish closes it. This story depends on less-noise's reconcile story, which adds close_agent to drop_gone_state (board.sh:1857). The lead adds that depends_on once less-noise is planned. Merge after it and after less-noise's name-cut story.

**Done when:**
- tests/reconcile_pull_test.sh: swarm.sh merge run from review-<slug>'s pane leaves it open and retired (review-<slug>-done). A later tidy --yes from another pane closes it, and no tab of the story is left. A check for an epic story and a backlog story in its own tab.
- reconcile run from the lead's pane closes an idle review-<slug> of a merged story at once.
- The same holds through drop_gone_state's close_agent path (a story whose file the pull removed); tests/pr_removes_story_test.sh passes.

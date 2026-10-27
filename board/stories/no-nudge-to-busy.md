---
kind: code
status: blocked
epic: board-pr-and-briefs
depends_on: [conduct-brief-hands-off]
needs: [conduct-brief-hands-off (conductor-hands-off): the conductor brief's rules and nudge sites (green_rule and the rest) as it rewrites them]
touches: [bin/lib/build.sh:green_rule, bin/lib/build.sh:give_up_rule, bin/lib/build.sh:stacked_rule, bin/lib/build.sh:clash_rule, commands/swarm.md:kept and no-agent arms' nudge lines, tests/nudge_idle_test.sh (new)]
estimate_lines: 100
easy: false
---

# Nobody sends a nudge to an agent that is still working

Uses conductor-hands-off's conduct-brief-hands-off: the conductor brief's nudge sites as it leaves them. tell_agent already refuses a nudge to a busy agent (bin/lib/agents.sh:1641); the noise is the attempts: 39 of 92 `tell:nudge` rows in this project's .swarm/events.tsv were refused 'is still working', 15 from the lead's pane (w20:p1) and 24 from others. Tally them by caller first and put the tally in the PR body. Then every nudge instruction gives one form in which the sender checks the wait's result before telling: `swarm.sh wait <slug> && swarm.sh tell <slug> nudge <file>`, run in the background, so a wait that times out, stalls or sticks sends nothing, and tell's own state check (agents.sh:1636-1641) covers the moment after. The sites: the conductor brief's (green_rule, give_up_rule, stacked_rule and clash_rule today, bin/lib/build.sh:983-1151; re-find them on conduct-brief-hands-off's result) and the lead's in commands/swarm.md (:158, :233).

**Done when:**
- The PR body has the events.tsv tally of refused tell:nudge rows by caller.
- tests/nudge_idle_test.sh (new) runs the form the rendered conductor brief gives against stub agents: one busy until the wait's timeout, and one whose wait ends stalled, get no tell attempt (no tell:nudge row, no herdr prompt sent); an idle one is told. It fails when the form drops the wait or its result check.
- The same test finds that form at every nudge instruction in the rendered conductor brief and in commands/swarm.md.

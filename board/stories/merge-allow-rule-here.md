---
kind: lead
status: blocked
epic: merge-agent-setup
depends_on: [init-merge-allow-rule]
needs: [init-merge-allow-rule: init's merge-rule check and the step it prints]
touches: []
estimate_lines: 0
easy: true
---

# You: add the swarm.sh merge allow rule on each merge = agent board

This board runs merge = agent (.claude/swarm/config:6), and in v0.28.0 conductors were refused every merge as 'Merge Without Review'. **You:** add the allow rule `swarm.sh init` names to your Claude Code settings, for every merge = agent board you run on this machine. Lead: run `swarm.sh init` in each such project and confirm it prints no merge-rule step, then watch the next conductor merge.

**Done when:**
- `swarm.sh init` in swarm-dev, and in each other merge = agent project the user names, prints no merge-rule step.
- One conductor merge goes through after the rule is added: events.tsv has an ok `merge` line for a story PR merged from a conductor's pane, and that pane shows no 'Merge Without Review' denial.

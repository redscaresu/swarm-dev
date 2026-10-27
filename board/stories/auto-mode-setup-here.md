---
kind: lead
status: blocked
epic: merge-agent-setup
depends_on: [init-auto-mode-check]
needs: [init-auto-mode-check: init's auto mode step and --auto-mode-done]
touches: []
estimate_lines: 0
easy: true
---

# You: run auto mode's environment setup on this machine

The epic's auto mode lesson, the user's step. **You:** run auto mode's environment setup once on this machine, then confirm it with the command `swarm.sh init` prints (`swarm.sh init --auto-mode-done`) in each project you run a swarm in. Lead: run `swarm.sh init` and confirm it prints no auto mode step.

**Done when:**
- `swarm.sh init` in swarm-dev, and in each other project the user names, prints no auto mode step.

---
status: active
parent: less-noise
hld: 2026-10-25-swarm-dev-0-28
stage: v0.29.0
depends_on: []
---

# A merge = agent project is set up before its first conductor

init checks the swarm.sh merge allow rule and auto mode's setup, conductors do not start without the rule and say why, and the user's steps are done on this board.

A child of less-noise, split at planning (2026-10-26). Its stories were planned with the parent; the parent's Out of scope, Constraints and Your part apply.

**Done when:**
- init-merge-allow-rule: init checks for the swarm.sh merge allow rule and names the user's step
- init-auto-mode-check: init tells the user to run auto mode's setup, and knows when it was done
- conduct-merge-preflight: No conductor starts under merge = agent without the swarm.sh merge allow rule, and next says why
- merge-allow-rule-here: You: add the swarm.sh merge allow rule on each merge = agent board
- auto-mode-setup-here: You: run auto mode's environment setup on this machine

**Areas:** see each story's touches.

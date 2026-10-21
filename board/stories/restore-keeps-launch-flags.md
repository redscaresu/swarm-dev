---
kind: code
status: ready
risk: high
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/agents.sh:start_agent, hooks/hooks.json, tests/]
---

# An agent restored after a herdr restart keeps its guards

herdr restores a Claude pane with `claude --resume <id>` (herdr docs, session-state), which drops the
launch flags agents.sh:364 passes: `--model`, `--effort`, `--settings` (the SWARM_AGENT setting the
merge, main-checkout and pkill guards key on) and `--disallowedTools`. After the 2026-10-21 herdr
restart every builder ran without its guards.

start_agent reports the full resume command to herdr after start:
`herdr pane report-agent <pane> --source swarm --agent claude --state <s> -- claude --resume <id>
--model … --effort … --settings … --disallowedTools …` (within herdr's limits: 64 args, 8 KiB, no
apostrophes). Reporting makes swarm the lifecycle authority for that pane, which turns off herdr's
screen detection, so swarm-dev's hooks/hooks.json also report state (UserPromptSubmit → working,
Stop → idle, Notification → blocked) through `pane report-agent`, and `release-agent` on close.

**Done when:**
- With a herdr stub, start_agent's report-agent call carries every launch flag in resume form; a flag with an apostrophe makes start fail naming it.
- The hooks report working, idle and blocked to the stub on the matching Claude hook events.
- A manual check after a real herdr restart (PR body): a restored builder's `herdr pane process-info` argv has `--settings`, and its guard refuses a raw merge.

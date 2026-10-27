---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [hooks/hooks.json:timeouts, tests/hooks_json_test.sh (new)]
estimate_lines: 40
easy: true
risk: high
---

# Hooks get time limits that survive a loaded machine

On 2026-10-27, under swarm load (load 17; Microsoft Defender and Spotlight at 94% and 72% CPU scanning about 40 worktrees), the UserPromptSubmit hooks agent-state.sh and user-caught-reminder.sh timed out at their 5-second limit in the lead session and in agent panes, and Claude Code discarded their output (user, 2026-10-27). A timed-out agent-state.sh leaves herdr with a stale working or idle state, which plausibly explains tell refusing idle agents and false no-review alerts that night. Each hook does well under a second of work when the machine is quiet.

Raise every agent-state.sh and user-caught-reminder.sh entry in hooks/hooks.json from 5 to 30 seconds. Leave lead-stop.sh's 60 as it is.

This PR changes hooks/, a protected path: it waits for the user's merge.

**Done when:**
- A test reads hooks/hooks.json and fails if any agent-state.sh or user-caught-reminder.sh entry has a timeout under 30, or if the file does not parse.
- `make test` passes.

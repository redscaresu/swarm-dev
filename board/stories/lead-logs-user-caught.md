---
kind: code
status: ready
depends_on: []
touches: [hooks/hooks.json:UserPromptSubmit, hooks/user-caught-reminder.sh (new), tests/user_caught_reminder_test.sh (new), docs/reference.md:the lead]
estimate_lines: 90
easy: true
---

# The lead is reminded to log user-caught each time the user writes

commands/swarm.md:354-357 tells the lead to run `swarm.sh intervene user-caught "<what they found>"` the moment the user finds a problem before the swarm does. It is prose, and the lead skips it: on 2026-10-25 the user caught three problems and none was logged until the user asked how such things reach the retro. A rule the lead must remember is not enough.

Add a UserPromptSubmit hook, `hooks/user-caught-reminder.sh`, that adds one line of context to the lead's turn: "If this message points out a problem the swarm or the lead missed, log it first: swarm.sh intervene user-caught \"<what they found>\"." It runs only in a lead session in a swarm project (a project with .claude/swarm/config, and not an agent: an agent's environment has SWARM_GH_CALLER, which launch_file sets), and prints nothing elsewhere. It never blocks the prompt and stays within the 5-second hook timeout.

**Done when:**
- A test shows the hook prints the reminder for a lead session in a swarm project, and prints nothing for an agent session (SWARM_GH_CALLER set) or outside a swarm project; each case goes red if its condition is removed.
- hooks/hooks.json runs it on UserPromptSubmit beside agent-state.sh, and the plugin's hook tests and `make test` pass.
- docs/reference.md § The lead says the reminder exists and why.

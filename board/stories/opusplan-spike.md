---
kind: verify
status: ready
touches: [board/stories/sonnet-share.md (the findings section only)]
---

# Spike: can a builder run as `opusplan` unattended, and which setting moves its subagents off Opus

`swarm.sh cost` on infrafactory since 2026-10-01: builders are 66% of the estimated spend (code-risky
$439, code $246 of $1042), and nearly all of it is cache reads (2.37B tokens against 13.5M output): Opus
re-reading a long session on every turn. Two cheap levers to test before sonnet-share builds them:

1. **`--model opusplan`**: Opus in plan mode, Sonnet otherwise. A builder starts with `--permission-mode
   auto` today. Find out, in a throwaway git repo inside a herdr pane, started the way start_agent starts a
   builder: can a session started with `--model opusplan --permission-mode plan` plan, leave plan mode and
   build with no person approving the plan? If ExitPlanMode waits for approval, can it be approved
   non-interactively (a setting, a flag, a hook, or the conductor's `swarm.sh tell`)? Record which model
   each turn used, from the session's .jsonl `message.model`, so the switch to Sonnet is shown, not assumed.
2. **Subagent model**: which environment variable or setting makes a session's subagents (Agent/Task
   tool, Explore) run on Haiku or Sonnet while the main session stays on its own model. Check the Claude Code
   docs and release notes for the installed version; then prove it in a session: spawn one Explore subagent
   and show its model in the transcript.

Never point a session at the user's real config for anything but this throwaway repo, and never log in or
out. If a check needs a person (a login, an approval dialog only a human can answer), stop and reply naming it.

**Done when:**
- Appended to board/stories/sonnet-share.md under `## Spike findings (opusplan-spike)`: for each lever, works / does not work / works with a condition, the exact flag or variable, the installed Claude Code version, and one line of evidence each (the command, and the `message.model` values seen).
- When the conductor re-runs the two evidence commands, they give the same models.
- No change to bin/swarm.sh.

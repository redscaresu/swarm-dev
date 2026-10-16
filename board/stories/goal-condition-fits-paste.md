---
kind: code
status: ready
epic: goal-paste
depends_on: []
touches: [bin/swarm.sh, tests/goal_test.sh, docs/method.md, .claude-plugin/plugin.json]
risk: high
---

# The /goal message stays short enough that Claude Code runs it as a command

On 2026-10-16, three of four infrafactory builders under `goal = 5` (rehearsal-passthrough args, exit-code and runner-stream) were closed `cleared-on-error` because `send_goal` found no goal set within 60s. Their session logs show why. Claude Code collapsed the pasted text into a `<pasted_content>` block and queued it as a prompt, so the `/goal` was never run as a command. Their conditions were 1192 to 2212 characters after whitespace was squeezed. The one that worked, exec-paths, was 698. `GOAL_MAX_CHARS=4000` (swarm.sh:2031) checks only Claude Code's cap on the condition, not the paste collapse.

Fix: `goal_condition` no longer inlines the story's **Done when** and **From review** blocks. The condition names them by reference: every item under **Done when:** and **From review** in `<board>/stories/<slug>.md`, which the brief told the builder to implement and which is already in its session, holds and is shown in this session. It then adds the reply sentence, the `IMPOSSIBLE:` escape and the bound, as today. The whole `/goal` message must be at most GOAL_SEND_MAX characters. Measure the collapse threshold in a herdr pane on the installed Claude Code. GOAL_SEND_MAX sits safely below it, and the comment records the version and the measured value. `story` refuses a message over GOAL_SEND_MAX, naming the story, before anything is sent (it replaces the GOAL_MAX_CHARS check). Also, when `goal_entry` finds no goal, `send_goal` looks in the session log for a queued prompt that starts with the `/goal` it sent, and when it finds one, its die message says the /goal was pasted as text, not run. docs/method.md § goal says the condition refers to the story by path. Bump .claude-plugin/plugin.json to the next patch version of what main holds.

**Done when:**
- `bash tests/goal_test.sh` passes with a case where a story's **Done when** is over 2,500 characters: the `/goal` message `story` would send is at most GOAL_SEND_MAX, names the story's path, and ends with the bound sentence.
- A case where a stub session log holds a `queued_command` whose prompt is the pasted `/goal` makes `send_goal` fail with a message containing "pasted as text".
- The PR quotes the herdr measurement: the length at which a pasted `/goal` collapsed, and the Claude Code version.
- Each new test is shown failing with the fix reverted by a cp backup.
- `.claude-plugin/plugin.json` holds the next patch version of what main holds.

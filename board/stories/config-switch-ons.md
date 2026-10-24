---
kind: lead
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [.claude/swarm/config]
after: safer-faster-swarm
easy: false
estimate_lines: 5
---

# After the release, the lead makes every .claude/swarm/config change in one PR, held for the user

after: safer-faster-swarm. The only story that edits swarm-dev's .claude/swarm/config, a file only the lead edits. After the release: drop lessons_file, set `fallback_reviewer = <model>` (sonnet unless the model-fit table says otherwise), and set `escalate_ladder = sonnet,opus,fable`, all in one PR. The user agreed to the Fable rung's usage on 2026-10-21 (costs: money is for cloud resources only), so the lead merges it. The lead then runs one epic and posts each escalate event with its trigger beside the model-fit table's rows, and links a PR reviewed under a codex limit with its fallback line.

**Done when:**
- The config PR's diff drops lessons_file and sets fallback_reviewer and escalate_ladder; once the user has merged it, `swarm.sh config` prints both and no lessons_file.
- After one epic, its escalate events are posted here with their triggers and models (or 'none fired'), and a PR reviewed by the fallback is linked (or 'no codex limit during the epic').

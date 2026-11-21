---
kind: lead
status: ready
epic: release-ci
depends_on: []
touches: [board/hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md:§ Open questions (item 4)]
estimate_lines: 3
easy: true
---

# Lead, optional: try stable and swarm-dev-pre enabled one per project, and record the answer to open question 4

Needs no other story by depends_on. Planned with `after: release-ci`, so an untried trial never holds the epic. It uses release-refs' pre-marketplace branch, which exists by then.
- In a throwaway CLAUDE_CONFIG_DIR, install swarm-dev@swarm-dev and swarm-dev@swarm-dev-pre. Enable one in project A and the other in project B, through each project's `.claude/settings.json` `enabledPlugins` (HLD:562-564; the spike found that adding the same marketplace again per project fails, HLD:531-534).
- Start Claude Code in each. Record which version's hooks load in each, and whether both load anywhere (HLD:210-211: both at once load the hooks twice).
- Record the answer, with Claude Code's version and the commands, under HLD open question 4 in a board PR. Or drop the story.

**Done when:**
- A merged board PR records under HLD open question 4 which plugin's hooks loaded in each project, with the Claude Code version and the commands; or the lead dropped the story with `swarm.sh drop`.

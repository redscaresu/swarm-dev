---
kind: lead
status: blocked
blocked_by: [skill-swarm-dev, cold-start-swarm-first-run]
epic: cold-start
depends_on: [skill-swarm-dev, cold-start-swarm-first-run]
touches: []
---

# Fresh session check: a clean Claude Code with only swarm-dev, asked 'how do I use swarm-dev?', loads the skill

Runs on main after skill-swarm-dev and cold-start-swarm-first-run merge, before the version bump, so a failure is fixed without a second bump. The lead makes a throwaway git repo and a throwaway config: CLAUDE_CONFIG_DIR=$(mktemp -d), so there is no memory, no global CLAUDE.md and no other plugin. This user's normal config has ~/.claude/CLAUDE.md and other plugins with SessionStart hooks. In that config the lead adds swarm-dev's local checkout as a marketplace and installs it. **You:** log in to that throwaway config (OAuth is per config dir; --bare needs ANTHROPIC_API_KEY or provider credentials and only resolves skills by /name, so it does not test auto-loading). Then **You:** accept the folder trust prompt (AGENTS.md: never accepted for the user). The lead asks 'how do I use swarm-dev?' and posts the answer and the transcript lines showing the Skill call. It then runs /swarm there (outside herdr it must say so and stop) and inside herdr: swarm.sh init offer, brief asked once, decline gives an empty brief, a second /swarm does not ask, and an empty board shows the flow. **You:** read the answer and say go for the bump, or name what is wrong; anything wrong becomes a new story. The lead deletes the throwaway repo and config dir after.

**Done when:**
- The transcript shows a Skill tool call for swarm-dev:swarm-dev that the model made itself (not typed as /swarm-dev), and the answer names swarm.sh init, the trust prompt, /hld <title> and /swarm.
- /swarm in the throwaway repo asks the three brief questions once; after a decline .claude/swarm/brief.md exists and is empty, and a second /swarm does not ask.
- On the empty board /swarm prints the flow in about five lines and suggests /hld <title>.
- The user's go is recorded on this story before cold-start-release starts.

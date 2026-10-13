---
status: active
depends_on: []
---

# Someone who installs swarm-dev today can use it with no help: their agent knows what it is, sets the project up, and asks for the brief

A new user's agent sees only what the plugin ships: the four commands, `bin/swarm.sh` and
`docs/method.md`. The setup steps and the "ask the user for the brief" rule live in swarm-dev's own
AGENTS.md (:25-28), which a user's project never has. `swarm.sh init` (story swarm-init, swarm-dev#67)
already copies the board; this epic covers the rest of the first run.

**Done when:**
- The plugin ships a skill (`skills/<name>/SKILL.md`) whose description makes an agent load it when asked how to use swarm-dev, how to set a project up, or why `/swarm` stopped. It says what swarm-dev is, the first-run steps (`swarm.sh init`, trust the folder, `/hld <title>`, `/swarm`), where `/swarm` stops for the user, and the commands; for detail it points at `${CLAUDE_PLUGIN_ROOT}/README.md` and `docs/method.md` and copies neither. A test fails when the skill names a command or `swarm.sh` subcommand that does not exist, or when its description is missing the trigger phrases.
- `/swarm` (commands/swarm.md), when `.claude/swarm/brief.md` is missing, asks the user once for their commit trailers, where credentials live and commands that must never run, writes the brief from the answers (inventing nothing), and goes on; a user who declines gets an empty brief and is not asked again.
- `/swarm` on an empty board (no HLD, epic or story) explains the flow in about five lines (design, epics, stories, builds, and where it stops for the user) and suggests `/hld <title>`.
- `/swarm`'s description begins "Start here".
- README Getting started matches: install, `swarm.sh init`, trust, `/hld`, `/swarm`; the brief question is mentioned. README, the skill and PR descriptions go through the humanizer (AGENTS.md).
- A fresh Claude Code session in a new git repo with only the plugin installed (no memory, no CLAUDE.md), asked "how do I use swarm-dev?", loads the skill and answers with those steps. This is a `lead` story: the lead runs it and posts the answer.
- plugin.json is bumped once, after agent-state-from-the-session has released, so this ships in its own release.

**Out of scope:** `swarm.sh init` itself (swarm-init); the unattended lead loop (`/loop /swarm`) and merge authority; project-specific rules, which belong in each project's AGENTS.md.

**Constraints:** commands and the skill are Markdown the plugin loads; no new runtime dependency. bash 3.2 for any swarm.sh change. Keep the skill short; detail stays in README and method so there is one source. A skill's location and front matter follow the Claude Code plugin docs; the first story checks them and `claude plugin validate .` passes.

**Your part:** approve the stories after scoping. The fresh-session check runs in a throwaway repo and needs nothing from you beyond reading the answer.

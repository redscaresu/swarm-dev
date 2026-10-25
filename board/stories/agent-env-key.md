---
kind: code
status: blocked
depends_on: [config-keys-back]
touches: [bin/swarm.sh:load_config, bin/lib/agents.sh:reserved_env, bin/lib/agents.sh:agent_cmd, bin/lib/agents.sh:start_agent, bin/lib/agents.sh:resume_agent, docs/reference.md]
estimate_lines: 200
easy: false
---

# agent_env: names every agent gets, set once per board

For 0.27.1, a patch release (user, 2026-10-25). On Azure Foundry no agent can start. launch_file
(bin/lib/agents.sh:293) passes AGENT_ENV (bin/lib/agents.sh:231), which has CLAUDE_CODE_USE_FOUNDRY
but not ANTHROPIC_FOUNDRY_RESOURCE, ANTHROPIC_FOUNDRY_API_KEY or the
ANTHROPIC_DEFAULT_{FABLE,OPUS,SONNET,HAIKU}_MODEL names. So Foundry is on with no endpoint, and every
pane stops with "Must provide one of the `baseURL` or `resource` arguments". A story's `env:` cannot
fix it: only builder roles read it (bin/lib/agents.sh:455), so the HLD co-author, reviewers,
planners and conductors never get the names.

- A new config key, `agent_env`: a space-separated list of variable names. Every agent, of every
  role, gets them, through the same path as a story's `env:` names, with the session's values.
  Conductors, resumes (resume_agent) and review agents included.
- Names follow story_env's rules: each matches `[A-Z_][A-Z0-9_]*` and is not reserved. A name that is
  not set in the session starting the agent is skipped with a warning, not refused: a board may run
  from a session without Foundry.
- docs/reference.md § The agents' environment documents the key, and that it is how a provider's key
  reaches agents.

**Done when:**
- A test shows a name in agent_env reaches a non-builder agent's launch file (e.g. role `hld`) and a
  builder's, and fails if agent_env is ignored.
- A test shows a reserved or malformed name is refused at config load, and an unset one is skipped
  with a warning.
- `make test` passes.

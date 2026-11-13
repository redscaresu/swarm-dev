---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:agent_env_names, tests/env_allowlist_test.sh:Bedrock pass-through cases, tests/env_allowlist_test.sh:foundry-off fixture, docs/reference-building.md:agent_env paragraph (§ Building, The agents' environment), docs/running.md:provider settings lines, AGENTS.md:agent environment rule]
estimate_lines: 80
easy: true
---

# Bedrock's key and model pins reach agents the way Foundry's do

The user moved the swarm from Azure Foundry to AWS Bedrock on 2026-11-12. agent_env_names (bin/lib/agents.sh) adds the session's `ANTHROPIC_FOUNDRY_*` and `ANTHROPIC_DEFAULT_*_MODEL` names unasked when `CLAUDE_CODE_USE_FOUNDRY` is 1 or true. Bedrock gets nothing like it. `CLAUDE_CODE_USE_BEDROCK` and `AWS_REGION` are on AGENT_ENV, but `AWS_BEARER_TOKEN_BEDROCK` (Bedrock's API key) and the `ANTHROPIC_DEFAULT_*_MODEL` pins are not. Without them an agent on Bedrock hangs at its first request instead of failing: a `claude -p --model sonnet` started with AGENT_ENV's names alone ran until a 60 s timeout (exit 124). With the two names added it replied at once. This board works around it with an `agent_env` line in `.claude/swarm/config`. On a subscription or Foundry session that line prints one warning per missing name at every agent start.

When `CLAUDE_CODE_USE_BEDROCK` is 1 or true, add the session's `AWS_BEARER_TOKEN_BEDROCK` and `ANTHROPIC_DEFAULT_*_MODEL` names in agent_env_names, beside the Foundry branch, with no duplicate when agent_env names them too. Do not add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` or `AWS_SESSION_TOKEN`: profile and SSO logins already reach agents through `HOME` and `AWS_PROFILE`, and a long-lived exported secret should stay opt-in through agent_env, as reference-building.md says. Update the agent_env_names comment. With neither flag on, agent_env_names adds none of these names on its own; names that agent_env or a story's env: list still pass as they do today. Do not edit `.claude/swarm/config`; the lead drops its agent_env line after this merges.

**Done when:**
- tests/env_allowlist_test.sh has a case for each of `CLAUDE_CODE_USE_BEDROCK=1` and `=true`: an agent's environment has `AWS_BEARER_TOKEN_BEDROCK` and all three of `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` with the session's values, and no agent_env line is needed
- A case with `CLAUDE_CODE_USE_BEDROCK=0` and no Foundry flag: neither name reaches the agent
- A case with both agent_env naming `AWS_BEARER_TOKEN_BEDROCK` and the flag on: the names agent_env_names returns hold `AWS_BEARER_TOKEN_BEDROCK` exactly once (count the returned names; the final environment collapses repeats, bin/lib/agents.sh:476)
- The existing foundry-off case (tests/env_allowlist_test.sh:379) inherits `CLAUDE_CODE_USE_BEDROCK=1` from PROVIDER and expects the Opus pin absent: set `CLAUDE_CODE_USE_BEDROCK=0` in that fixture so it still tests Foundry alone, and keep its expectation
- The `CLAUDE_CODE_USE_BEDROCK=1` case goes red with the new branch removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-building.md's agent_env paragraph names Bedrock beside Foundry as passing its key and model pins unasked; docs/running.md and AGENTS.md's agent environment rule say the same
- scripts/select-tests.sh --run passes

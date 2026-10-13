---
kind: code
status: blocked
blocked_by: [build-outcomes, opusplan-spike]
depends_on: [build-outcomes, opusplan-spike]
touches: [bin/swarm.sh (policy, ROLE_GROUPS, build_story's role line, CFG_/CONFIG_KEYS/load_config), tests/config_test.sh, tests/epic_test.sh, docs/method.md (§ Model and effort, config table), README.md (Cost and safety)]
---

# `sonnet_share`: build a fixed share of low-risk code stories on Sonnet, to measure against Opus

Every `kind: code` story has run on Opus (52 at high, 55 at xhigh in infrafactory's agents.tsv by
2026-10-13), so `swarm.sh outcomes` can never show whether Sonnet would have done as well. The user
approved an experiment on 2026-10-13. Add a role `code-sonnet` (`claude sonnet high`) to policy() and
ROLE_GROUPS' building group, and a config key `sonnet_share = N` (non-negative integer, default 0 = off).
With N > 0, build_story gives role `code-sonnet` to a `kind: code` story without `risk: high` when
`cksum` of its slug mod N is 0. The choice is deterministic, so a rebuild of the same story picks the
same role and the row in agents.tsv already says which arm a build was in; no new logging.

## Spike findings (opusplan-spike)

Claude Code 2.1.296. Throwaway repo, `claude -p` (print mode) with `--output-format stream-json --verbose`.
Model per turn read from each assistant event's `message.model`.

- **Lever 1, `--model opusplan`: does not work headless.** `claude -p --model opusplan --permission-mode plan`
  plans on `claude-opus-5-5` for every turn, then stops still in plan mode. It never reaches ExitPlanMode:
  on the second run the model asked for it and ToolSearch returned "No matching deferred tools found", so
  no Sonnet turn happens and nothing is edited. The session's `init` event reports `claude-sonnet-5-5`; that
  field is not the turn model. Not tested interactively: a fresh folder shows the trust prompt, which a
  person must accept. Until that is checked, leave `code-opusplan` out.
- **Lever 2, subagent model: works with a condition (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`).** Evidence:
  `CLAUDE_CODE_SUBAGENT_MODEL=haiku CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 claude -p --model opus
  --permission-mode auto --output-format stream-json --verbose "Use the Agent tool with subagent_type Explore
  to find where add is defined..."`: the main turns are `claude-opus-5-5`, the Explore subagent's turns
  (events with `parent_tool_use_id` set) are `claude-haiku-5-5`. Without `_FORCE`, the same
  `CLAUDE_CODE_SUBAGENT_MODEL=haiku` leaves the subagent on `claude-opus-5-5`, and so does no env at all.
  The variable alone does nothing for an Explore subagent; with `_FORCE` it overrides.

**Two more arms (user, 2026-10-13), shaped by opusplan-spike's findings:** if the spike shows `opusplan`
runs unattended, add a role `code-opusplan` (`claude opusplan high`, with whatever approval the spike found)
and split the sampled share between `code-sonnet` and `code-opusplan` by the same cksum rule (e.g. cksum mod
2N), so each arm is fixed per slug. If the spike names a subagent-model setting, add a config key
`builder_subagent_model` (default empty = unchanged) that start_agent passes to building roles only. If a
lever does not work, leave it out and say so in the PR.

**Done when:**
- With `sonnet_share = 0`, every role resolves as today (a test over code, code + risk high, docs, chore, verify).
- With `sonnet_share = 4`, a fixture set of code stories splits by the cksum rule, a `risk: high` story is always code-risky, docs/chore/verify are unchanged, and the started agent's agents.tsv row says `code-sonnet sonnet high`. Shown red on the old code.
- With the spike's levers present: a sampled story resolves to code-sonnet or code-opusplan by the rule, fixed per slug; with `builder_subagent_model` set, a building role's start carries the setting and a planning or conducting role's does not.
- A value that is not a non-negative integer is refused by load_config naming the key.
- The method's config table, § Model and effort and README's Cost and safety describe the key and that it ships off. No plugin.json bump: it ships in the next release story.

**Constraints:** ships off (docs/method.md: code that adds a setting merges with it off); turning it on is the lead story sonnet-share-on. When fable-on-call lands, its single role function absorbs this rule and its role-coverage test must include code-sonnet; only a story's first attempt is sampled, so a retry goes back to Opus.

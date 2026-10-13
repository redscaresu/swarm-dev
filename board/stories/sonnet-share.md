---
kind: code
status: blocked
blocked_by: [build-outcomes]
depends_on: [build-outcomes]
touches: [bin/swarm.sh (policy, ROLE_GROUPS, build_story's role line, CFG_/CONFIG_KEYS/load_config), tests/config_test.sh, tests/epic_test.sh, docs/method.md (§ Model and effort, config table), README.md (Cost and safety), .claude-plugin/plugin.json]
---

# `sonnet_share`: build a fixed share of low-risk code stories on Sonnet, to measure against Opus

Every `kind: code` story has run on Opus (52 at high, 55 at xhigh in infrafactory's agents.tsv by
2026-10-13), so `swarm.sh outcomes` can never show whether Sonnet would have done as well. The user
approved an experiment on 2026-10-13. Add a role `code-sonnet` (`claude sonnet high`) to policy() and
ROLE_GROUPS' building group, and a config key `sonnet_share = N` (non-negative integer, default 0 = off).
With N > 0, build_story gives role `code-sonnet` to a `kind: code` story without `risk: high` when
`cksum` of its slug mod N is 0. The choice is deterministic, so a rebuild of the same story picks the
same role and the row in agents.tsv already says which arm a build was in; no new logging.

**Done when:**
- With `sonnet_share = 0`, every role resolves as today (a test over code, code + risk high, docs, chore, verify).
- With `sonnet_share = 4`, a fixture set of code stories splits by the cksum rule, a `risk: high` story is always code-risky, docs/chore/verify are unchanged, and the started agent's agents.tsv row says `code-sonnet sonnet high`. Shown red on the old code.
- A value that is not a non-negative integer is refused by load_config naming the key.
- The method's config table, § Model and effort and README's Cost and safety describe the key and that it ships off; plugin.json bumped.

**Constraints:** ships off (docs/method.md: code that adds a setting merges with it off); turning it on is the lead story sonnet-share-on. When fable-on-call lands, its single role function absorbs this rule and its role-coverage test must include code-sonnet; only a story's first attempt is sampled, so a retry goes back to Opus.

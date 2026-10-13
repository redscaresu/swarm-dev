---
kind: lead
status: blocked
blocked_by: [sonnet-share]
depends_on: [sonnet-share]
touches: []
---

# Turn on `sonnet_share = 4` for infrafactory and read the first results

The user approved the experiment on 2026-10-13 ("I am ok with you experimenting a bit"). After the
release carrying sonnet-share, the lead sets `sonnet_share = 4` in infrafactory's
`.claude/swarm/config` (one line, its own PR), and after roughly 20 sampled builds compares
`swarm.sh outcomes` rows for `code-sonnet` and `code-opusplan` (if built) against `code`: merged or not, review rounds (tells),
findings fixed, closes per story, cost. The lead posts the comparison for the user.

**Phase 2, after the user's phase 1 decision (user, 2026-10-13):** the lead sets
`builder_subagent_model = haiku` in infrafactory's config (its own PR), so builders' search and test
subagents run on Haiku. First check that it took: sonnet-share passes the variables through `--settings`
(herdr cannot pass environment variables), which the spike did not test, so read the first such builder's
.jsonl and confirm its subagent turns (`parent_tool_use_id` set) show a Haiku `message.model`; if not, stop and file a fix. Never with phase 1 still running: changing both at once would hide which change
moved the outcomes. After roughly 20 Opus builds with it on, the lead compares their `swarm.sh outcomes`
rows (cost, tells, findings fixed, attempts) with the Opus builds before the switch, and posts it. The same
early stop applies: two builds in a row that fail to reach a green, reviewed PR set it back to empty.

**You:** read the comparison and say keep, widen, or turn it off. Stop early and set it back to 0 if
two sampled builds in a row fail to reach a green, reviewed PR.

**Done when:** phase 1: the setting has been on for at least 20 sampled builds (or stopped early by the rule
above), the comparison is posted, and the user's keep / widen / off is recorded here. Phase 2: the same, for `builder_subagent_model`, with the user's keep / off recorded here.

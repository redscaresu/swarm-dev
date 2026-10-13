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
`swarm.sh outcomes` rows for `code-sonnet` against `code`: merged or not, review rounds (tells),
findings fixed, closes per story, cost. The lead posts the comparison for the user.

**You:** read the comparison and say keep, widen, or turn it off. Stop early and set it back to 0 if
two sampled builds in a row fail to reach a green, reviewed PR.

**Done when:** the setting has been on for at least 20 sampled builds (or stopped early by the rule
above), the comparison is posted, and the user's keep / widen / off is recorded here.

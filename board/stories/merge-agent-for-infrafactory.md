---
kind: lead
status: blocked
epic: leaner-faster-swarm
depends_on: [merge-holds-costs-money, release-this-epic]
touches: [infrafactory: .claude/swarm/config, infrafactory: docs/stories/*.md (costs: money only)]
---

# infrafactory runs merge = agent, with every money-costing story held for the user

The user approved it on 2026-10-16 ("sounds good", after the lead showed that it had merged every
infrafactory PR that day under merge = human, none of them costing money), on condition that
money-costing PRs still wait for them. merge-holds-costs-money adds that hold; release-this-epic
ships it.

Once the release is installed, the lead reads every open infrafactory story (ready, blocked and
later) and sets `costs: money` on each whose merge can spend money (merge-holds-costs-money's
definition), then sets `merge = agent` in infrafactory's .claude/swarm/config with a comment naming
the user's condition, in one infrafactory PR the lead merges. Real-cloud steps stay `kind: lead`
stories as before. **You:** none.

**Done when:**
- The merged infrafactory PR is linked here and lists each story it marked `costs: money`, or says
  none qualified and why.
- `swarm.sh config merge` in infrafactory prints `agent`.
- The first infrafactory conductor run after it merges a PR itself, and any `costs: money` story it
  meets is left for the user (its report is quoted here).

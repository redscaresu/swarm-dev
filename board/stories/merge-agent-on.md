---
kind: lead
status: blocked
blocked_by: [flow-speedups-release]
epic: flow-speedups
depends_on: [flow-speedups-release]
touches: [.claude/swarm/config]
risk: high
---

# Turn on merge = agent for swarm-dev; infrafactory stays human

After the release is published, the lead runs `claude plugin update swarm-dev@swarm-dev` and adds `merge = agent` to swarm-dev's .claude/swarm/config in its own PR, which the lead merges (the user approved the switch on 2026-10-15). The lead checks `swarm.sh config merge` in both projects, without editing infrafactory, then runs the next epic and checks that the conductor merged, reconciled and started newly ready stories itself.

**Done when:**
- On main, `swarm.sh config merge` in swarm-dev prints agent (from .claude/swarm/config), and in infrafactory prints human.
- In the first conductor run after the switch, the session .jsonl shows at least one merge by literal PR number with `--match-head-commit`, followed by reconcile and the start of a story that unblock readied in the same run. Otherwise the lead files a story naming what the conductor did instead.

**From review (binding; overrides the scope above where they differ):**
- No restart is needed: the lead runs `claude plugin update swarm-dev@swarm-dev` and calls the new script directly. The lead merges the config PR under its standing authority, so nothing here waits on the user.
- Depends only on flow-speedups-release; ruleset-not-strict was done on 2026-10-15 before the board PR.

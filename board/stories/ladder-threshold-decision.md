---
kind: lead
status: blocked
epic: ladder-cost
depends_on: [rung-cost-block]
needs: [rung-cost-block (the per-rung block in flow's cost section)]
touches: []
estimate_lines: 10
easy: true
---

# Lead: decide this board's step-up threshold from the per-rung figures

Uses rung-cost-block's per-rung block. The epic's Your part. Once the block has merged, the lead runs `flow --since <the v0.30.0 build's start>` once (after `gh api rate_limit`) and puts the per-rung table, and the share of builds that reached Fable, in front of the user with the 0.27 baseline from docs/features.tsv. The plugin default stays 3. Only if the user decides on another value for this board does the lead open a PR setting `step_up_findings` in .claude/swarm/config; `swarm.sh merge` holds a `.claude/` change for the user (merge-holds), and `merge --board` refuses a file outside board/ (bin/lib/merge.sh:279-283). The v0.31.0 retro reads the same figures again.

**You:** decide the threshold for this board from the figures (keep 3, or a value the figures support).
**You:** if it changes, merge the held config PR.

**Done when:**
- The figures and the user's decision are recorded in the release-v0-30-0 story's PR (or the retro notes), and either the board's config is unchanged or the config PR has merged.

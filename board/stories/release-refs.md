---
kind: lead
status: blocked
epic: release-ci
depends_on: [release-ref-spike]
needs: release-ref-spike (the ruleset JSON it proved on the copy with the release credential)
touches: [refs/heads/stable (new), refs/heads/prerelease (new), refs/heads/pre-marketplace (new), rulesets on stable, prerelease and pre-marketplace (new)]
estimate_lines: 0
easy: true
risk: high
---

# Lead: create stable, prerelease and pre-marketplace at the newest v0.31.x tag; You: add the rulesets release-ref-spike proved

Uses release-ref-spike's ruleset JSON, which it proved on the copy with the credential release-workflow will use.
- Lead: read the newest v0.31.x tag on origin when this runs (`git ls-remote --tags origin 'v0.31.*'`), not v0.31.2. It is v0.31.3 on 2026-11-21. Take its peeled commit.
- Lead: create `stable` and `prerelease` at that commit through the API. Nothing names them yet: main's marketplace.json still says `./`.
- Lead: push `pre-marketplace` with one signed commit holding .claude-plugin/marketplace.json: name `swarm-dev-pre`, one plugin `swarm-dev` whose source is `{source: url, url: https://github.com/redscaresu/swarm-dev.git, ref: prerelease}` (HLD:206-209). An orphan branch is enough. Run the pinned validator on it first (`npx --yes @anthropic-ai/claude-code@2.1.284 plugin validate <dir>`, ci.yml:117). It never moves after.
- **You:** add the three rulesets from release-ref-spike's file to redscaresu/swarm-dev: no-delete on all three branches with no bypass; `update` and `non_fast_forward` on stable and pre-marketplace; `non_fast_forward` on prerelease; the last two let the admin role bypass. You, the lead and every agent share one gh login (bin/lib/agents.sh:388), so the bypass cannot tell you apart (see contradictions).
- Lead, after: read the rulesets back, and check that each branch points at the commit above (L2).

**Done when:**
- `gh api repos/redscaresu/swarm-dev/branches/<b>` returns 200 for stable, prerelease and pre-marketplace. stable and prerelease name the newest v0.31.x tag's commit. pre-marketplace's marketplace.json is named swarm-dev-pre, names the prerelease ref and passed the pinned validator. `gh api repos/redscaresu/swarm-dev/rulesets` lists the three rulesets with the rules and bypass release-ref-spike recorded.

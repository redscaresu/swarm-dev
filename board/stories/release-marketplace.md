---
kind: lead
status: blocked
epic: release-ci
depends_on: [release-refs, release-install-proof]
needs: release-refs (stable at the newest v0.31.x tag, under the rulesets); release-install-proof (the pinned validator passing the url+ref form, and installs that follow stable and do not move when the marketplace change merges)
touches: [.claude-plugin/marketplace.json:plugins source, docs/reference-merging.md:§ Releases (a new paragraph after its first line: the stable and prerelease refs)]
estimate_lines: 15
easy: true
risk: high
---

# Lead: main's marketplace.json points every install at the stable ref; You merge it

Uses release-refs' stable branch and rulesets, and release-install-proof's answers. No agent builds it (the epic). .claude-plugin/ is held, so the user merges it.
- Lead, before: stable is at the newest v0.31.x tag's commit and its ruleset is on (L2). If release-install-proof recorded a red validator, stop.
- Lead: on a branch from main, set marketplace.json's plugin source to `{"source": "url", "url": "https://github.com/redscaresu/swarm-dev.git", "ref": "stable"}` (HLD:197-201). Add a paragraph after § Releases' first line (docs/reference-merging.md:1061) saying: every install follows stable; the release workflow moves only prerelease; stable moves only at a stage's end, when the lead moves it after the user clears the exit epic; so a fix reaches other machines then; swarm-dev-pre follows prerelease. Run the humanizer pass. plugin-validate must be green on the PR.
- **You:** merge it.
- Lead, after: in a throwaway CLAUDE_CONFIG_DIR, `claude plugin marketplace add redscaresu/swarm-dev` and install. It must give stable's version. Check that the lead's own install keeps its version after its next update, and that stable and prerelease are unchanged (L2).

**Done when:**
- main's marketplace.json names the stable ref in the url form, and plugin-validate was green on its PR. After the merge, a fresh install from redscaresu/swarm-dev installs stable's version, the lead's install keeps its version after an update, and stable and prerelease still name the v0.31.x tag. docs/reference-merging.md § Releases says installs follow stable and stable moves only at a stage's end, and doc_check passes.

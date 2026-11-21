---
kind: lead
status: blocked
epic: release-ci
depends_on: [release-ref-spike]
needs: release-ref-spike (the public copy, its three branches and its rulesets, under which the rollback force-push runs)
touches: [the throwaway copy, a new GitHub issue on redscaresu/swarm-dev (the rollback entry's), board/epics/release-client.md:Done when (5) and (6), board/epics/release-ci.md:Done when (5)]
estimate_lines: 6
easy: true
risk: high
---

# Lead: on the copy, prove installs follow stable, ignore prerelease, survive the marketplace change, and roll back; You: agree where the binary rollback is proved

Uses release-ref-spike's public copy and its rulesets. Every install runs in a throwaway CLAUDE_CONFIG_DIR, as the HLD's spike did (HLD:519-540).
- Validator (Done when 6): on a PR in the copy, set marketplace.json's plugin source to `{source: url, url: <copy>.git, ref: stable}`. The copy's plugin-validate job runs the pinned 2.1.284 (ci.yml:117), which the spike never tried. If it is red, record the error and stop: a newer pin is a new story (held .github/).
- Before that PR merges, add the copy's marketplace the way users do (`claude plugin marketplace add <owner>/<copy>`) and install swarm-dev@swarm-dev. Set the copy's stable and prerelease at its v0.31.x tag commit.
- Merge the copy's PR, then `claude plugin marketplace update` and `claude plugin update`: the version and files must not move (Done when 6). Move prerelease forward one version: no move (Done when 4). Move stable forward: it follows (the positive control).
- Rollback (Done when 5): add a swarm-dev-pre marketplace from the copy's pre-marketplace branch. Put prerelease at version B, with a marker line in one hook that A lacks, and install. Force-push prerelease back to A, then update and restart. Record the plugin.json version and the hook. If they do not go back, find and record the steps that do (uninstall and install, a cache clear), for rollback-docs.
- The binary half of Done when 5 needs binary-fetch's wrapper, which this epic does not depend on. **You:** agree that release-client's real-release check proves it; release-client depends on binary-fetch and release-ci (codex, critic). Lead, on a board PR after your yes: add to release-client.md's Done when (5) that with prerelease moved back one version, an update and a restart run the older version's binary; say in release-ci.md's Done when (5) that its binary half is proved there; and in release-client.md's Done when (6) name AGENTS.md's patch rule and release paragraph in place of `:146-148` and `:282-287`, which have moved (the paragraph is at AGENTS.md:312-320 now) (critic).
- Lead: open an issue on redscaresu/swarm-dev for the rollback entry: docs/lead-by-hand.md:3-4 gives each entry an open issue. Record its URL.

**Done when:**
- This story's file records: the copy's plugin-validate run on the url+ref marketplace.json, green, or red with its error; the installed version and files unchanged after the copy's marketplace PR merged and after prerelease moved, and changed after stable moved; the swarm-dev-pre install's plugin.json version and hook marker after the move back and a restart, or the steps that brought them back; the issue URL. The board PR that moves the binary half of Done when (5) into release-client.md, with your yes in its body, has merged. A red validator, or a downgrade that nothing brings back, stops the epic until the lead adds a story.

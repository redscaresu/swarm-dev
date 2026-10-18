---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [merge-guard-hook, main-checkout-guard, env-allowlist, board-state-out-of-git, escalated-block-out-of-git, reconcile-drops-backup, pr-removes-story, merge-admin, guard-pattern-kill]
touches: [.claude-plugin/plugin.json]
easy: false
estimate_lines: 5
---

# Release 0.22.0: the safety slice

One of three releases for this epic, so each group reaches infrafactory as soon as it is done (user, 2026-10-17). It ships the merge guard, the main-checkout guard, the env allowlist, and board state out of git, which protect every run after it. A release is a lead step, not a build, so it sits one past the 3-deep chain limit.

The lead bumps .claude-plugin/plugin.json to 0.22.0 and writes notes for the merged PRs since the last tag (humanized). It merges with `swarm.sh merge --release --head <sha> <url>`, then runs `claude plugin update swarm-dev@swarm-dev`. New conductors pick up the new version; the lead's own session needs a restart, or it reads commands/*.md from the new cache directory. After installing, the lead runs `swarm.sh dash --check` if it has shipped.

**Done when:**
- v0.22.0 is tagged and published, and every PR it names is an ancestor of the tag (`git merge-base --is-ancestor`).
- `claude plugin list` shows 0.22.0 installed.
- The next infrafactory conductor started after it runs 0.22.0 (its pane's `swarm.sh version`).

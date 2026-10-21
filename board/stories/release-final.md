---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [merge-queue, red-main-gets-a-fixer, restore-keeps-launch-flags, close-spares-live-agents, api-error-stall, review-on-green, release-docs-gate, agents-md-catch-up]
touches: [.claude-plugin/plugin.json]
easy: false
estimate_lines: 5
---

# Release 0.24.0: main protection, restart safety and the docs catch-up

Re-scoped by the user on 2026-10-21 so the safety fixes do not wait on telemetry. It ships the merge queue, a red main's fixer, guards kept across a herdr restart, a close that spares live builders, the stall detector, review-on-green and the release docs gate, with the docs for everything 0.22.0 and 0.23.0 shipped (agents-md-catch-up). The rest of the epic goes out in 0.25.0 (release-epic-close).

The lead bumps .claude-plugin/plugin.json to 0.24.0 and writes notes for the merged PRs since the last tag (humanized). It merges with `swarm.sh merge --release --head <sha> <url>`, then runs `claude plugin update swarm-dev@swarm-dev`. New conductors pick up the new version; the lead's own session needs a restart, or it reads commands/*.md from the new cache directory. After installing, the lead runs `swarm.sh dash --check` if it has shipped.

**Done when:**
- v0.24.0 is tagged and published, and every PR it names is an ancestor of the tag (`git merge-base --is-ancestor`).
- `claude plugin list` shows 0.24.0 installed.
- The next infrafactory conductor started after it runs 0.24.0 (its pane's `swarm.sh version`).

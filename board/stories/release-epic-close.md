---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [codex-test-stray-perl, wait-pr-test-timeout-zero, docs-review-readme, docs-review-reference, escalate-ladder-step-up, escalate-ladder-triggers]
after: safer-faster-swarm
touches: [.claude-plugin/plugin.json]
---

# Release 0.25.0: the rest of the epic, and the newcomer docs

Split from release-final by the user on 2026-10-21. Ships every safer-faster-swarm story not in 0.24.0: the escalation ladder (off until config-switch-ons), the observability stories (intervention-count, ci-time-trend, agent-liveness-events, dash-check; prediction-scores waits for 0.26, lead 2026-10-22: it failed its builds and nothing in 0.25 needs it), next-plans-unblocked-epics, review-prompt-checklist, swarm-upgrade, herdr-state-events and ci-on-ubuntu-26, with the newcomer docs reviews. It closes the epic: cut it once no other agent story of the epic is open.

The lead lands a docs PR covering every behaviour change since v0.24.0 (README, AGENTS.md, docs/, commands/*.md, humanized), bumps .claude-plugin/plugin.json to 0.25.0, writes humanized notes naming that docs PR, merges with `swarm.sh merge --release --head <sha> <url>`, then runs `claude plugin update swarm-dev@swarm-dev` and `swarm.sh dash --check`.

**Done when:**
- v0.25.0 is tagged and published, and every PR it names is an ancestor of the tag.
- `claude plugin list` shows 0.25.0, and no agent story of the epic is open.

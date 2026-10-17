---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [tests-fast, epic-command, remove-plan-hld, fold-reports, remove-lessons, wait-pr, dataset, merge-guard-hook, env-allowlist, escalate-ladder-step-up]
touches: [AGENTS.md:steps table, useful commands, pre-PR list]
easy: false
estimate_lines: 40
---

# The lead brings the rest of AGENTS.md in line with the epic

AGENTS.md is the lead's (AGENTS.md:70). One PR beside the docs-review stories. The pre-PR list uses make test. The steps table and the useful-commands list match the epic: /epic and no /plan-hld; flow for cost, features and review-yield; no lessons; wait-pr, dataset and step-up; the merge guard; env:. The PR also deletes the epic file if the docs-review PRs left it.

**Done when:**
- AGENTS.md on this PR has no /hld, /plan-hld, `swarm.sh cost`, `swarm.sh lessons`, `swarm.sh features` or `swarm.sh review-yield`, and names make test, wait-pr and dataset.

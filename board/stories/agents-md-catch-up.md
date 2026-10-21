---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [tests-fast, epic-command, remove-plan-hld, fold-reports, remove-lessons, wait-pr, dataset, merge-guard-hook, env-allowlist]
touches: [AGENTS.md:steps table, useful commands, pre-PR list]
easy: false
estimate_lines: 40
---

# The lead brings the rest of AGENTS.md in line with the epic

AGENTS.md is the lead's (AGENTS.md:70). One PR beside the docs-review stories. The pre-PR list uses make test. The steps table and the useful-commands list match the epic: /epic and no /plan-hld; flow for cost, features and review-yield; no lessons; wait-pr, dataset and step-up; the merge guard; env:. The PR also deletes the epic file if the docs-review PRs left it. It also rewrites the top of AGENTS.md for a newcomer, a person or an agent opening the repo cold (user, 2026-10-17). The first screen says what swarm-dev is in two sentences, the four checks, and the first three commands in order (`swarm.sh init`, `/epic <title>`, `/swarm-dev:swarm`), with what each one leaves behind. It then points to method.md and llms.txt for the rest. Anything a newcomer does not need on day one moves below that point or into reference.md.

**Done when:**
- AGENTS.md's first 40 lines contain the two-sentence summary, the four checks and the three first commands, and no setting or command that `swarm.sh` does not have (doc-check passes).
- docs-review-readme's fresh-agent test is run from AGENTS.md as well as the README: an agent given only AGENTS.md reaches `swarm.sh init` and `/swarm-dev:swarm`, and its transcript is linked on the story.
- AGENTS.md on this PR has no /hld, /plan-hld, `swarm.sh cost`, `swarm.sh lessons`, `swarm.sh features` or `swarm.sh review-yield`, and names make test, wait-pr and dataset.

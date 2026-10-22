---
kind: docs
status: blocked
epic: safer-faster-swarm
depends_on: [board-prep, env-allowlist-spike, board-state-out-of-git, escalated-block-out-of-git, reconcile-drops-backup, pr-removes-story, board-state-dash-readers, after-key, sonnet-easy-only, plan-epic-size-cap, epic-command, plan-epic-child-epics, remove-plan-hld, fold-reports, flow-epic-totals, subagent-cost, model-fit-table, time-in-state, ci-health, incidents, lead-queue-wait, rework, dataset, recurring-kinds, remove-lessons, merge-guard-hook, wait-pr, fallback-reviewer, escalate-ladder-step-up, escalate-ladder-triggers, init-like-infrafactory, ci-board-fast-path, tests-fast, split-slow-tests, dash-project-anywhere, dash-three-defects, dash-golden-frames, dash-merge-gauges, dash-check, agent-entry-points, doc-check, env-allowlist]
touches: [docs/*.md, commands/*.md, templates/, docs/assets/*, tests/doc_check_known.txt:docs, commands and templates entries]
easy: false
estimate_lines: 280
---

# Review docs/, the command files, templates and diagrams against the code after the epic

Needs every other pre-release story of the epic merged. Review docs/*.md, commands/*.md (each description line naming the request that should trigger it), templates/ and the diagrams in docs/assets against the code as it then stands: every claim, command, flag and path must match, and each section is cut to what a person needs. Remove their entries from tests/doc_check_known.txt. Run the humanizer skill over the changed prose, and say so in the PR. It touches no file docs-review-readme touches, so the two run side by side.

**Done when:**
- tests/doc_check_test.sh passes with tests/doc_check_known.txt empty of docs/, commands/ and templates/ entries.
- The PR body lists each file reviewed with what changed.
- grep finds no /hld, /plan-hld or HLD step in docs/*.md, commands/*.md or the diagram sources in docs/assets, and every commands/*.md description names a request.
- #365 follow-ups (backlog conductor, 2026-10-23): `next` is no longer read-only, since it starts conductors, and `merge --board` no longer only notes. AGENTS.md:64, skills/swarm-dev/SKILL.md:43, README.md and docs/method.md:26 say otherwise; fix them, and take `next` out of READ_ONLY_COMMANDS in bin/swarm.sh. commands/swarm.md's wait step handles `next`'s `started:`, `no conductor started:` and start-warning lines, and says when the lead deletes an uncollected report.

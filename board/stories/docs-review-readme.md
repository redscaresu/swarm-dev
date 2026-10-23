---
kind: docs
status: ready
epic: safer-faster-swarm
depends_on: [board-prep, env-allowlist-spike, board-state-out-of-git, escalated-block-out-of-git, reconcile-drops-backup, pr-removes-story, board-state-dash-readers, after-key, sonnet-easy-only, plan-epic-size-cap, epic-command, plan-epic-child-epics, remove-plan-hld, fold-reports, flow-epic-totals, subagent-cost, model-fit-table, time-in-state, ci-health, incidents, lead-queue-wait, rework, dataset, recurring-kinds, remove-lessons, merge-guard-hook, wait-pr, fallback-reviewer, escalate-ladder-step-up, escalate-ladder-triggers, init-like-infrafactory, ci-board-fast-path, tests-fast, split-slow-tests, dash-project-anywhere, dash-three-defects, dash-golden-frames, dash-merge-gauges, dash-check, agent-entry-points, doc-check, env-allowlist]
touches: [README.md, llms.txt, tests/doc_check_known.txt:README.md and llms.txt entries]
easy: false
estimate_lines: 200
---

# Review README.md and llms.txt against the code after the epic, and check a fresh agent finds the first steps

Needs every other pre-release story of the epic merged. Review README.md and llms.txt against the code as it then stands: every claim, command, flag and path must match, and each section is cut to what a person needs to start. Remove README's entries from tests/doc_check_known.txt. Run the humanizer skill over the changed prose, and say so in the PR. Then a fresh agent (`claude -p` with no memory, in a temp dir holding a local clone of this branch), given 'set up swarm-dev for this repo', must find swarm.sh init and the first /swarm-dev:swarm from llms.txt or the README; quote its answer in the PR. The check by repo URL against main is after-release-checks'. This and docs-review-reference are the last stories before the release.

**Done when:**
- tests/doc_check_test.sh passes with no README.md or llms.txt entry left in tests/doc_check_known.txt.
- The PR body lists each README section reviewed with what changed, and quotes the fresh agent's answer naming swarm.sh init and /swarm-dev:swarm.
- grep finds no /hld, /plan-hld or HLD step in README.md.
- after-release-checks (2026-10-22) found `/swarm-dev:swarm` first in prose at line 47 and `swarm.sh init` at line 70. A three-line quick start (install, `swarm.sh init`, `/swarm-dev:swarm`) sits under the intro, above the image, so both appear as text in the first 20 lines.
- Obsidian is optional, and README says so (user, 2026-10-22): nothing runs it, but `init` writes `Board.base` and the `.obsidian/` lines. README names it under Requirements as optional, or under Watching it, with what it shows (open the board folder as a vault; `Board.base` groups stories by status and epic).
- Started on 2026-10-23 while upgrade-until-done (#391) and release-upgrades-agents were still open. Before the PR opens, merge origin/main and recheck the upgrade and release sections against whatever of those two has merged by then. Say in the PR which of them it covers.

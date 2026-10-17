---
kind: lead
status: blocked
epic: safer-faster-swarm
depends_on: [release-final, flow-epic-totals, model-fit-table, subagent-cost, tests-fast, split-slow-tests, ci-board-fast-path, dash-check, agent-entry-points]
touches: [board/stories/sonnet-share-on.md:phase 2 (only if over 10%)]
after: safer-faster-swarm
easy: false
estimate_lines: 5
---

# After the release, the lead measures merge-ins, CI times, subagent share, dash agreement and a fresh agent on main

after: safer-faster-swarm. The lead posts here: flow's merged-in-main share over the epic's window, beside the 55% baseline; the CI time of the epic's last code PR (target under 3 minutes); a throwaway board-only PR's run, with the three jobs' later steps skipped and every required check green in under 1 minute; builder subagents' share of build cost from the model-fit table, written into sonnet-share-on's phase 2 if it is over 10% (that phase already plans the builder_subagent_model = haiku trial); one real builder session's subagent turns matching one of subagent-cost's two shapes, read by keys only; `swarm.sh dash --check` on swarm-dev and infrafactory; and a fresh agent given only the repo URL finding swarm.sh init and /swarm-dev:swarm.

**Done when:**
- Each number and run is posted with the command or URL it came from.
- A CI time over its target, a board-only run over 1 minute or with a step not skipped, a dash --check mismatch, a subagent log in neither shape, or a fresh agent that misses the first steps has a filed story linked here.
- If the subagent share is over 10%, sonnet-share-on's phase 2 names it.

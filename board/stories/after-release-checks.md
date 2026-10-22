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

## Results after v0.24.0 (2026-10-22)

- **Merged-in-main share:** 62% (16 of 26, `swarm.sh flow --since 2026-10-17`), 63% (17 of 27, `flow --epic safer-faster-swarm`), against the 55% baseline. Worse. Filed main-merge-in-causes.
- **Last code PR's CI:** #330 9m22s (run 39682994418), #327 9m36s, #334 10m46s; the `test` job alone is about 9m20s. The target is under 3 minutes: missed. Filed ci-shard-tests.
- **Board-only PR:** #341 (run 39698424271) took 12s, and every job's later steps were skipped. Met.
- **Builder subagents' share of build cost:** the model-fit `subagents` block is empty. The tests-fast builder's .jsonl has 0 `parent_tool_use_id` and 0 `isSidechain` turns, and builders spawned no subagents, so the share is 0%. That is under 10%, so sonnet-share-on's phase 2 is unchanged. A session's `subagents/agent-*.jsonl` (91 isSidechain turns, claude-opus-5-5) matches subagent-cost's second shape. None came back in neither shape.
- **dash --check:** every figure agrees, on swarm-dev and infrafactory.
- **Fresh agent on main's README:** `/swarm-dev:swarm` first appears in prose at line 47, and `swarm.sh init` at line 70. Folded into docs-review-readme's Done when.
- **ci_health:** printed `gh failed` and dropped 26 of about 31 PRs. Filed flow-ci-health-gh-errors.
- Epic cost so far: $985.35 over 83 builds (`flow --epic safer-faster-swarm`).

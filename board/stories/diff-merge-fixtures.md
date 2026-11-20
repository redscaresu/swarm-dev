---
kind: code
status: blocked
epic: port-checks
depends_on: [diff-run-core]
needs: diff-run-core (tests/diff_run.sh: the fixture format with env, the per-stream compare, the shims)
touches: [tests/diff_fixtures_merge.sh]
estimate_lines: 170
---

# Merge fixtures run each tree's own swarm.sh merge under fixed stubs

Uses diff-run-core's fixture format. tests/diff_fixtures_merge.sh builds on merge_fixture.sh's setup and stub answers (fresh, its gh and herdr stubs), not on its merge(): that runs the harness checkout's own swarm.sh and folds stderr into stdout (tests/merge_fixture.sh:15,301). Each fixture's command is `merge <url>`, run by the tree under test with merge()'s env (SWARM_MERGE_POLL=0 and the zero waits, tests/merge_fixture.sh:300-301), so no poll count follows the clock. Fixtures: direct, merge queue, --board, a costs: money hold, red CI on main, merged elsewhere while waiting. Every stub answer is fixed.

**Done when:**
- (1) Two copies of one tree compare clean on every merge fixture three runs in a row (under `--times 3` once diff-run-order is on main); the PR quotes the output and wall time. (2) On a worktree copy without .git, a one-byte change to a held: line in one tree's bin/lib/merge.sh is red, naming its fixture, and so is one merge output line moved from stdout to stderr. (3) Every gh call the fixtures make is answered by the stubs: the run shows no shim refusal line.
- scripts/select-tests.sh --run passes

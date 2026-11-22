---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [.github/workflows/ci.yml:shellcheck gate, .github/workflows/ci.yml:test-shard gate, .github/workflows/ci.yml:plugin-validate gate, .github/workflows/diff-run.yml:gate, .github/workflows/go.yml:gate, .github/workflows/go.yml:checks' conditions, .github/workflows/macos.yml:gate, .github/workflows/speed.yml:gate, tests/board_only_test.sh:workflow check]
estimate_lines: 180
risk: high
---

# Every job that runs CI's gate sets up Go before it, and every step after it still skips a board-only PR

After the switch, board-only.sh's version-only path runs the binary, and CI runs the base's copy of the gate (contradiction 4), so the PR after the switch needs Go in the gate's job. In the seven jobs that run the gate (ci.yml's shellcheck, test-shard and plugin-validate; diff-run.yml; go.yml; macos.yml; speed.yml), setup-go, pinned by the SHA each file already uses and with cache: false, runs before the gate. A job that set Go up after the gate does so no more. go.yml's ten steps gated on steps.setup.outcome (go.yml:66-149) also need the gate's no, as a conjunct, so a board-only PR skips them though Go is set up. The gate still runs ci_gate.py; nothing runs the binary there yet.
board_only_test.sh's workflow check (:150-200) covers all five files: each gated job sets Go up before its gate step, and every step after the gate runs only when the gate says no, never under ||. diff_base_test.sh's diff-run.yml check (:160-176) keeps passing. The user merges it (.github/).

**Done when:**
- (1) board_only_test.sh passes. On a worktree copy without .git where one go.yml step drops the gate's no, or one job's setup-go moves after its gate, it is red naming the step; the PR quotes it. (2) On this PR, each of the seven gate steps prints the verdict it printed on the PR before, with setup-go ahead of it; the PR quotes them. (3) zizmor passes on the PR. (4) diff_base_test.sh passes. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

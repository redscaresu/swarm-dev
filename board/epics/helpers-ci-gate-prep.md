---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit]
---

# The tests, fixtures and CI jobs the ci_gate switch needs are ready on the bash

Before the switch, the tests that reach inside ci_gate drive swarm.sh from outside, the differential run has ci_gate fixtures, and every gated CI job has Go ahead of its gate.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** The tests the stories name pass on the bash and drive it only from outside, and each rewritten check is shown to fail when the rule it guards is broken. Each fixture in tests/diff_fixtures_ci_gate.sh records ci_gate's check-runs read on its head. The run is clean, head against head, and red, naming each fixture, when ci_gate.py's judge is broken. All seven gated jobs set up Go before scripts/board-only.sh runs, and tests/board_only_test.sh fails when a job lacks it.

**Stories:**
- [ci-gate-tests-outside](../stories/ci-gate-tests-outside.md)
- [ci-gate-diff-fixtures](../stories/ci-gate-diff-fixtures.md)
- [ci-gate-ci-go](../stories/ci-gate-ci-go.md)

**Out of scope:**
- Any Go port (the other children)

**Your part:**
- You merge ci-gate-ci-go, which changes .github/.

**Areas:**
- ci-gate-tests-outside: [tests/wait_pr_cache_test.sh:python3 wrapper, ps match and direct head runs, tests/wait_pr_expected_test.sh:direct head run, tests/board_only_test.sh:fixture (main's base0 files), tests/merge_base_moved_test.sh:on_board cases, tests/merge_ci_budget_test.sh:wait records folder, tests/merge_rules_test.sh:file read that dies silent]
- ci-gate-diff-fixtures: [tests/diff_fixtures_ci_gate.sh]
- ci-gate-ci-go: [.github/workflows/ci.yml:shellcheck gate, .github/workflows/ci.yml:test-shard gate, .github/workflows/ci.yml:plugin-validate gate, .github/workflows/diff-run.yml:gate, .github/workflows/go.yml:gate, .github/workflows/go.yml:checks' conditions, .github/workflows/macos.yml:gate, .github/workflows/speed.yml:gate, tests/board_only_test.sh:workflow check]

---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit, helpers-ci-gate-core, helpers-ci-gate-cache]
---

# ci_gate's per-PR subcommands run as Go, compared case by case with the Python

base, head, files, the expected workflows, fixed, admin, behind, required and queue exist as Go modes of `_ci-gate`.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** Each of these modes has a tests/ci_gate_cases/<mode>.cases file: base, head, files, files-status, fixed, admin, behind, merged, required, age, queue and pushed. tests/ci_gate_cases_test.sh runs every one through the Python and the Go, compares output and exit code, and fails when either side alone is changed. No file under bin/ runs the Go.

**Stories:**
- [ci-gate-go-head](../stories/ci-gate-go-head.md)
- [ci-gate-go-files](../stories/ci-gate-go-files.md)
- [ci-gate-go-head-expected](../stories/ci-gate-go-head-expected.md)
- [ci-gate-go-fixed-admin](../stories/ci-gate-go-fixed-admin.md)
- [ci-gate-go-behind](../stories/ci-gate-go-behind.md)
- [ci-gate-go-rules](../stories/ci-gate-go-rules.md)
- [ci-gate-go-queue](../stories/ci-gate-go-queue.md)

**Out of scope:**
- The wait on main, the stop and queued modes and the records (helpers-ci-gate-main)

**Your part:**
- You merge every port here (protected merge package). The carve-out covers every story, as in the parent.

**Areas:**
- ci-gate-go-head: [internal/merge/head.go, internal/merge/head_test.go, tests/ci_gate_cases/head.cases]
- ci-gate-go-files: [internal/merge/files.go, internal/merge/files_test.go, tests/ci_gate_cases/files.cases, tests/ci_gate_cases/files-status.cases]
- ci-gate-go-head-expected: [internal/merge/expected.go, internal/merge/expected_test.go]
- ci-gate-go-fixed-admin: [internal/merge/fixed.go, internal/merge/fixed_test.go, tests/ci_gate_cases/fixed.cases, tests/ci_gate_cases/admin.cases]
- ci-gate-go-behind: [internal/merge/behind.go, internal/merge/behind_test.go, tests/ci_gate_cases/behind.cases, tests/ci_gate_cases/merged.cases]
- ci-gate-go-rules: [internal/merge/rules.go, internal/merge/rules_test.go, tests/ci_gate_cases/base.cases:go mark, tests/ci_gate_cases/required.cases, tests/ci_gate_cases/age.cases]
- ci-gate-go-queue: [internal/merge/queue.go, internal/merge/queue_test.go, tests/ci_gate_cases/queue.cases, tests/ci_gate_cases/pushed.cases]

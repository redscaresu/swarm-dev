---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit, helpers-ci-gate-core, helpers-ci-gate-cache, helpers-ci-gate-modes]
---

# ci_gate's wait on main, its records and its stop and queued modes run as Go

The poll of CI on main, the rerun rule, the wait records, the main wait and the stop and queued modes exist as Go modes of `_ci-gate`.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/merge has mainpoll.go, rerun.go, records.go, mainwait.go, stop.go and queued.go with Go tests. tests/ci_gate_cases/main.cases, stop.cases and queued.cases pass through the Python and the Go, compared on output and exit code, and fail when either side alone is changed. tests/merge_queue_test.sh keeps the assertion its go_check column names. No file under bin/ runs the Go.

**Stories:**
- [ci-gate-go-main-poll](../stories/ci-gate-go-main-poll.md)
- [ci-gate-go-main-rerun](../stories/ci-gate-go-main-rerun.md)
- [ci-gate-go-main](../stories/ci-gate-go-main.md)
- [ci-gate-go-stop](../stories/ci-gate-go-stop.md)
- [ci-gate-go-records](../stories/ci-gate-go-records.md)
- [ci-gate-go-queued](../stories/ci-gate-go-queued.md)

**Out of scope:**
- Switching the bash callers (helpers-ci-gate-switch)

**Your part:**
- You merge every port here (protected merge package). The carve-out covers every story, as in the parent.

**Areas:**
- ci-gate-go-main-poll: [internal/merge/mainpoll.go, internal/merge/mainpoll_test.go]
- ci-gate-go-main-rerun: [internal/merge/rerun.go, internal/merge/rerun_test.go]
- ci-gate-go-main: [internal/merge/mainwait.go, internal/merge/mainwait_test.go, tests/ci_gate_cases/main.cases]
- ci-gate-go-stop: [internal/merge/stop.go, internal/merge/stop_test.go, tests/ci_gate_cases/stop.cases]
- ci-gate-go-records: [internal/merge/records.go, internal/merge/records_test.go]
- ci-gate-go-queued: [internal/merge/queued.go, internal/merge/queued_test.go, tests/ci_gate_cases/queued.cases]

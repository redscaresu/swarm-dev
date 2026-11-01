---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# flaky-tests

HLD Goal 13 (v0.31.0): CI is green on the first run. #698 watch_opened_test's temp-dir cleanup, and queue_test and codex_test's timing cases, no longer flake.

**Done when:**
- stage: v0.31.0
- tests/watch_opened_test.sh's EXIT trap (line 14) no longer races a running watch (comment at 75, sleep at 87): the watch is stopped before the root is removed; 20 runs through make test TESTS=<file> at JOBS at most 4 are green and the count is in the PR.
- tests/queue_test.sh and tests/codex_test.sh wait on a condition, not a fixed sleep, in the cases that flaked; the cause is named in each PR; 20 runs each green.
- docs/features.tsv row: CI reruns per 100 PRs, read from `flow ci_health` (red runs per PR and flakes; 15 over 119; bar under 3); docs/lead-by-hand.md's #698 entry (105-111) removed.
- The goal is a flake rate, not three named files: `flow ci_health`'s flaky runs per 100 PRs under the bar, with each flaky file the v0.30.0 build saw (timeouts_test, ci_health, dash_widths, upgrade, live_logs, events, next) fixed or named in the PR.

**Out of scope:**
Test-file timeouts and the cap (machine-usable); ci.yml shard changes (protected); new SLOW or SERIAL entries.

**Constraints:**
- stage: v0.31.0. Depends on no epic (tests only). Three stories, none risk: high: the lead plans it alone (AGENTS.md's small-epic rule).
- Tests run only through make test or scripts/select-tests.sh --run, never a file by hand; prove each fix by 20 runs at JOBS at most 4.
- No new sleeps; tests/timeouts_test.sh's within and timeout rules.

**Areas:** tests/watch_opened_test.sh, tests/queue_test.sh, tests/codex_test.sh, tests/test_helpers.sh (a shared wait-for helper if two files need one), docs/features.tsv:Goal 13 row, docs/lead-by-hand.md:#698

**Your part:**
- none

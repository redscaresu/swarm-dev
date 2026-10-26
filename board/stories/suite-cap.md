---
kind: code
status: blocked
epic: test-speed
depends_on: [flow-builder-test-runs]
needs: [flow-builder-test-runs: its edits to tests/flow_test_runs_test.sh, which this story makes export HOME under its own root]
touches: [scripts/test.sh:runs_log block, scripts/test.sh:cap slot, scripts/test.sh:cleanup, tests/test_cap_test.sh, tests/sleep_scale_test.sh:cap nesting case, README.md:test-cap line in More, tests/flow_test_runs_test.sh:HOME export]
estimate_lines: 180
easy: false
risk: high
---

# A machine-wide cap on concurrent test suites, off by default

A safety path: it sits in front of every make test. The cap is the file ~/.swarm/test-cap: a whole number; absent, empty or 0 means no cap; anything else is refused with a message. Only scripts/test.sh reads it. It is no SWARM_* variable (scripts/test.sh:34) and no CONFIG_KEYS entry. With a cap of N, a run takes a slot atomically: `mkdir ~/.swarm/test-slots/<i>` for i in 1..N, writing its PID inside. mkdir succeeds for one run only, so two runs started together cannot both take a cap-1 slot, and no ordering can leave both waiting. While no slot is free it waits, polling, and prints that it waits and on how many. A slot whose PID is dead is reclaimed by renaming it aside first, so two reclaimers cannot both win. Take the slot before the start log line. The per-project marks (:133-137,161) stay as they are for others/at_once, so the 0.27 baseline still compares. A nested run (TEST_RUNS_LOG exported empty, :136) skips the cap and takes no slot, so make test inside make test (tests/sleep_scale_test.sh:100) never deadlocks. With no cap file, nothing under ~/.swarm is created. cleanup (:170-187) frees the slot, on an interrupt too. The cap=1 nesting case goes in tests/sleep_scale_test.sh, which is already SERIAL (Makefile:18-19), so no shard is added (test_shard_test: SLOW+SERIAL is 8 of 8). Ships off; no story turns it on (HLD Design § Test speed keeps no cap). README.md's More list gets the cap line in this PR; agents-md-test-selection documents it in AGENTS.md.

Review fix (skeptic): tests/flow_test_runs_test.sh starts top-level runs with `env -u TEST_RUNS_LOG` (:34, :53, :56, :75, :78) and does not export HOME, so a cap file in the real HOME would gate it. Any test that unsets TEST_RUNS_LOG to start a top-level run exports HOME under its own mktemp root, and tests/test_cap_test.sh checks that with a grep over tests/*_test.sh, as sleep_scale_test.sh:33-37 does for HOME and CLAUDE_CONFIG_DIR.

**Done when:**
- tests/test_cap_test.sh, with HOME at its own temp dir and stub test files that log their start and end: with no cap file a run passes and creates nothing under $HOME/.swarm; with cap 1, two runs started together from two temp project dirs never overlap; a slot held by a live PID makes a run print that it waits and start only after that PID exits; a slot of a dead PID is reclaimed; an interrupted run frees its slot.
- tests/sleep_scale_test.sh gains a case: with its HOME holding cap 1 and TEST_RUNS_LOG at a temp file (a top-level run that takes the slot), make test over a fixture that itself runs make test finishes inside the file's existing bound.
- With HOME holding a cap of 1, `make test TESTS='tests/flow_test_runs_test.sh tests/sleep_scale_test.sh'` passes, leaves no slot under that HOME, and creates nothing under the real ~/.swarm.

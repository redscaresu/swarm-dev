---
kind: code
status: blocked
epic: test-speed
depends_on: [codex-runs-no-tests, suite-cap]
needs: [codex-runs-no-tests: bin/swarm.sh:codex_review as it changes it (the exec line and its tests in tests/codex_test.sh), suite-cap: scripts/test.sh's runs_log block and cleanup as it changes them]
touches: [bin/swarm.sh:codex_review, scripts/test.sh:runs_log block, scripts/test.sh:--one timeout branch, tests/codex_test.sh:limit-kill case, tests/test_file_timeout_test.sh, docs/reference.md:audit log, README.md:TEST_FILE_TIMEOUT line in More]
estimate_lines: 75
easy: true
---

# codex-review's timeout kill and make test's TEST_FILE_TIMEOUT kill log a reap event

Needs codex-runs-no-tests' bin/swarm.sh:codex_review and suite-cap's scripts/test.sh runs_log block, both of which this story edits again. Two kill sites each append a `reap` line to .swarm/events.tsv naming what was killed. (1) codex_review's codex_minutes timeout, where stop_codex runs before `die "codex skipped: timed out"` (bin/swarm.sh:726-727). It calls record_event reap with target `codex-${SWARM_STORY:-$1}`, as the codex-limit incident does (:719), and outcome `timed out after <N> min`. (2) scripts/test.sh's TEST_FILE_TIMEOUT kill, in the .timeout branch (:69-74). test.sh is not sourced from swarm.sh and has no record_event, so it writes append_event's 5-field line itself: UTC time, reap, the file, HERDR_PANE_ID or -, `TIMEOUT after <n>s`, with tabs and newlines stripped (bin/lib/agents.sh:692-696). It writes to the events.tsv beside the run's test-runs.tsv (dirname of runs_log, :132-135). The path reaches the --one jobs in a non-SWARM_ variable, which --one unsets before the test runs (:40). Nothing is written when runs_log is empty (a nested run, :136). Document the reap line in reference.md's audit log (:879-900), because retro-report reads it (board/epics/retro-report.md:13). Update README.md:164-165's TEST_FILE_TIMEOUT line in this PR.

**Done when:**
- tests/codex_test.sh's limit-kill case asserts exactly one `reap` line in the project's .swarm/events.tsv with target codex-<base or story> and the timed-out outcome; a codex that finishes writes none.
- tests/test_file_timeout_test.sh, with TEST_RUNS_LOG at a temp file, asserts one five-field `reap` line naming the timed-out file in the events.tsv beside it; a file that finishes inside the limit writes none, and so does a run with TEST_RUNS_LOG set empty.

---
status: active
hld: 2026-10-25-swarm-dev-0-28
stage: v0.28.0
depends_on: []
---

# A builder's local test run is small

A builder's local test run is small: before a push a builder runs the test files mapped to the functions it changed and falls back to the full suite only for a file the map does not know; codex can run no tests; a machine-wide suite cap exists, off by default; flow's test_runs counts partial runs; kills are logged as reap events for the retro. The p90 reading is taken after v0.28.0 is installed (v0.29.0 release story, then the retro). HLD Goal 4, Design § Test speed. Adopts slow-test-files and ci-three-minutes (Rollout § Stages names them here): this epic's /plan-epic PR sets their `epic:` and `status: ready`, rewrites their touches as file:part and corrects slow-test-files' stale 20-to-55-minute text to Appendix A's figures.

**Done when:**
- A selector maps a changed `file:function` (bin/lib/*.sh functions, bin/lib/*.py, bin/swarm.sh dispatch arms, commands/*.md, hooks/*, scripts/*) to the tests/*_test.sh files that exercise it, and README.md, AGENTS.md and docs/ to doc_check_test, features_test and llms_test; a changed file with no map entry selects the full suite; a test fails on any tracked file under bin/, scripts/, commands/, hooks/ and docs/ the map leaves out; the selector's PR posts a dry run over the last 20 merged PRs with the files each would select and their quiet-run seconds from .swarm/test-runs.tsv. scripts/test.sh:138-143 already takes TESTS=.
- AGENTS.md's 'Before you open a PR' block says run the selector before a push and that CI's sharded run is the gate; the plugin's builder brief is unchanged (the selector is swarm-dev's own runner, scripts/test.sh:34 unsets SWARM_*; HLD Design § Test speed: fail toward more, never fewer); doc_check passes.
- flow's test_runs reports builder runs (branch story/*) of every filter, full fallback runs included, apart from the `all` baseline, with median and p90 (bin/lib/flow_test_runs.py:28 keeps only all today; tests/flow_test_runs_test.sh pins the old exclusions and is updated); docs/features.tsv has a test-selection row with metric `flow test_runs: builder p90 s`, bar 300 s, and the 0.27 baseline (median 1050 s, p90 1391 s on 35 full runs, Appendix A); tests/features_test.sh passes.
- codex cannot run the suite: scripts/test.sh and the Makefile `test` target refuse when run under codex's environment, keyed on a variable real codex 0.164 sets (recorded from one real `codex exec review` run and cited in the PR), or `codex exec review` runs under `-c sandbox_mode=read-only` proven on a real run (bin/swarm.sh:700 passes no flags today; `exec review` has no -s flag); tests/codex_test.sh's passthrough and limit-kill pins still pass, and the stub test pins the variable or flag. The PPID-1 check is a lead step after the first real review (your_part), not the proof.
- A machine-wide cap on concurrent suites is a file outside any project (for example ~/.swarm/test-cap), read only by scripts/test.sh, absent by default (no cap); marks for the cap live in a machine-wide directory while the per-project marks at scripts/test.sh:133-137 stay for others/at_once (so the 0.27 baseline still compares); a nested run (TEST_RUNS_LOG='' exported, scripts/test.sh:136) skips the cap; a test with cap=1 runs sleep_scale_test inside it without deadlock and a fake mark shows a run past the cap waits. Documented in AGENTS.md, not in CONFIG_KEYS or reference.md's settings table (doc_check_test.sh:63-79 ties that table to CONFIG_KEYS).
- codex_review's limit kill (bin/swarm.sh:661-700) and scripts/test.sh's TEST_FILE_TIMEOUT kill each append a `reap` line to .swarm/events.tsv naming what was killed; a test per site; the retro reads them (retro-report).
- slow-test-files: the PR lists the top 10 files by quiet-run seconds before and after and each changed file is at least 30% faster on a quiet run; coverage unchanged. ci-three-minutes: its PR shows per-shard times from its own CI runs, and SLOW/SERIAL moves update ci.yml's matrix and tests/test_shard_test.sh; the 10-PR median is read at the v0.29.0 release story.

**Out of scope:**
Changing CI's shard count beyond what ci-three-minutes needs; a usage reading; running swarm-dev's swarm from main; the stall misread under make test (liveness-signals owns it, by process tree, so it never reads the marks); a direct `bash tests/x_test.sh` under codex (AGENTS.md forbids direct runs; the refusal sits where make and scripts/test.sh run); any change to the run-mark format (no other epic reads the marks).

**Constraints:**
- Selection fails toward running more, never fewer (HLD Design § Test speed).
- scripts/test.sh unsets every SWARM_* var but SWARM_SLEEP_SCALE (scripts/test.sh:36) and is not sourced from swarm.sh: the cap and the codex refusal read a file or a non-SWARM_ variable.
- tests/sleep_scale_test.sh and tests/test_runner_test.sh pin make test's behaviour (failing file fails the run, SERIAL after parallel, nothing left running); 96 of 111 test files call bin/swarm.sh, which sources every bin/lib/*.sh (bin/swarm.sh:437-449), so the map is by function, not by file.
- Tests only through make; stress and load runs use at most 4 CPUs and are torn down (HLD Appendix C).
- This epic alone edits scripts/test.sh and the Makefile; touch docs/features.tsv as `docs/features.tsv:test-selection row` and reference.md as `docs/reference.md:test_runs section`.
- The cost to watch: flow ci_health red runs; read at the v0.29.0 release story and the v0.31.0 retro.
- bash 3.2, shellcheck, loose_match_test, make test, claude plugin validate; humanizer over README/docs/AGENTS.md prose.
- Order: clash-by-part's AGENTS.md story goes after this epic's 'Before you open a PR' story (AGENTS.md is a shared hot file, commands/plan-epic.md:69; the sections differ).

**Areas:** scripts/test.sh, scripts/ (the selector), Makefile:test and SLOW and SERIAL, bin/swarm.sh:codex_review, bin/lib/flow_test_runs.py, .github/workflows/ci.yml, tests/ (slowest files, flow_test_runs_test, codex_test, test_shard_test, the map test), docs/reference.md:test_runs section, docs/features.tsv:test-selection row, AGENTS.md:Before you open a PR, README.md

**Your part:**
Lead: after the first real codex review under the installed v0.28.0, run `ps -axo pid,ppid,command | grep tests/ | awk '$2 == 1'` and record the (empty) result for the release-v0.29.0 story's PR. No other human step; the cut is the release story's (stage-gating's constraints).

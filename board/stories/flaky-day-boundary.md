---
kind: code
status: ready
epic: flaky-tests
depends_on: []
touches: [tests/dash_widths_test.sh:setup (TZ, cost row :73), tests/ci_health_test.sh:setup (TZ, dates :51)]
estimate_lines: 70
easy: true
---

# dash_widths_test and ci_health_test hold when a run crosses midnight

Needs no other story. Cause: both started just before UTC midnight and failed just after it, in the same run window. dash_widths_test started 2026-10-30T23:59:58Z (run 41147355075) and failed 'at 160 columns the status bar...' (:174), which wants '$24.00 today' from a cost row dated `date +%F` at :73. ci_health_test started 23:59:13Z (run 41147495165) and failed 5 refresh checks from :225 on, against dates fixed at :51. bin/ already has a clock override for dash: SWARM_DASH_NOW (bin/lib/dash.sh:230, dash_render.py:12). Use it with matching fixture dates in dash_widths_test. ci_health_test makes UTC timestamps (:49-51) and flow_ci_health reads UTC days (bin/lib/flow_ci_health.py:169, 429), and CI runs in UTC, so a TZ setting does not fix it: fix its dates so they stay valid for the whole bounded run whatever the UTC day, or show that the checks do not depend on the day. Check that every date in each file, fixture and code, follows TZ. Do not edit tests/test_helpers.sh (flaky-watch-reap owns it): keep the few lines local to each file. Audit: 33 of 181 test files write today-dated fixtures (grep at 2a07799c). The PR lists each, with whether a check reads a today-relative figure. Name the ones at risk for a follow-up; do not edit them here. Run the 20 runs one at a time, JOBS=1.

**Done when:**
- In the PR, runs 41147355075 and 41147495165 are named with their failing checks and start times, quoted from their logs.
- Midnight proof in a worktree copy without .git: each unfixed file, started under a minute before local midnight (a TZ chosen for it, half- or quarter-hour zones allowed), fails. With the fix, the same start passes. The PR quotes both.
- The midnight proof also starts ci_health_test under a minute before UTC midnight with TZ=UTC; unfixed it fails, fixed it passes.
- 20 runs each of make test TESTS=tests/dash_widths_test.sh JOBS=1 and TESTS=tests/ci_health_test.sh JOBS=1, one at a time, all green. The counts are in the PR.
- The PR lists the audit of the 33 today-dated test files, with the at-risk ones named.
- No file under bin/ changes, and shellcheck is clean on the touched files.

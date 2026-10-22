---
kind: code
status: ready
depends_on: []
touches: [bin/lib/flow_ci_health.py, tests/flow_test.sh]
easy: false
estimate_lines: 150
---

# flow names the test files that fail and then pass on the same commit

ci_health counts flaky runs (bin/lib/flow_ci_health.py:62) but not which test failed. On 2026-10-22, three reruns of the same commit went green: tests/codex_test.sh twice on main (6822719, 75aef21) and tests/wait_pr_test.sh once on #352. Finding them took reading job logs by hand. For each run whose failed attempt was followed by a green one on the same SHA, read the failed jobs' logs (`gh run view --log-failed`, or the job logs API), collect the `FAIL tests/<file>` lines, and print a table of test file, flaky runs, last seen and an example run URL, worst first. Count each run once per file. If a log can't be read, name the run under the section rather than drop it, as ci_health already does for gh errors.

**Done when:**
- tests/flow_test.sh: fixture runs with a failed then green attempt on one SHA, whose log fixture holds `FAIL tests/a_test.sh`, list a_test.sh with 1. A run red on every attempt is not counted. An unreadable log is named, not dropped.
- `swarm.sh flow` on this repo lists codex_test.sh and wait_pr_test.sh from 2026-10-22, quoted in the PR.

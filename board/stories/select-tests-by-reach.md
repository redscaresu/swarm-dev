---
kind: code
status: blocked
epic: test-speed
depends_on: [select-changed-functions]
needs: [select-changed-functions: scripts/select_tests.py:changed_functions, the changed function and arm list this story walks from]
touches: [scripts/select_tests.py:reach, scripts/test-map.tsv:bin rows, tests/select_tests_test.sh:reach cases]
estimate_lines: 230
easy: false
---

# The selector runs only the tests that reach a changed bin/ function

Needs select-changed-functions' changed_functions list in scripts/select_tests.py, and the `all` bin rows in scripts/test-map.tsv, which this story narrows. Test reachability: walk callers through a static call graph over bin/swarm.sh and bin/lib/*.sh (a function's callers are the functions whose body names it) up to the dispatch arms. Select every test that names any function on that caller chain, since tests source bin/lib directly (tests/sleep_scale_test.sh:44-46,94-96), or names a reached arm's command word anywhere in its text, which catches wrappers such as flow_holds_test.sh's holds() (tests/flow_holds_test.sh:68). Fall back to the full suite when unsure: `full` from select-changed-functions, a dynamic call (`"cmd_${x}"`), a test that runs swarm.sh with no arm word in its text, or a function no test reaches. The map may carry explicit override rows for a known wrapper. Dry run: over the last 20 merged PRs (gh pulls/<n>/files, with previous_filename), print each PR's selection (files, `full` or `none`). Run each distinct selection once with JOBS=4 (HLD Appendix C) and read its seconds and at_once back from .swarm/test-runs.tsv (flow_test_runs.py:36-37). For `full`, use Appendix A's quiet full median (1050 s). Post it in the PR.

**Done when:**
- tests/select_tests_test.sh pins, on fixture code and tests: a change in a function one arm reaches selects the tests that run that arm and not a test that runs only another arm; a test that sources the lib and calls a caller of the changed function is selected; a test that runs the arm through a wrapper function is selected; a dynamic call site, and a test that runs swarm.sh with no arm word, each select every test.
- The PR body holds the dry run over the last 20 merged PRs: per PR the files it would select (or full or none), and seconds with their at_once from .swarm/test-runs.tsv, each run at JOBS=4.

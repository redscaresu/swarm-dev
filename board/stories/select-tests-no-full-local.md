---
kind: code
status: ready
depends_on: []
touches: [scripts/select_tests.py:full fallback, scripts/select-tests.sh:--run, tests/select_tests_test.sh:local fallback cases, AGENTS.md:Before you open a PR]
estimate_lines: 80
easy: true
---

# select-tests --run leaves the full suite to CI

On 2026-11-15 an audit of `.swarm/test-runs.tsv` found 148 of 526 November local runs were full-suite
runs, taking 3 to 5 hours each with up to 12 runs at once, and only 1 of 244 finished full runs exited 0.
Most came from `scripts/select-tests.sh --run` falling back to the full suite when the map does not know a
changed file. CI's sharded run already covers the full suite in about 9 minutes.

Change `--run`'s fallback: when the selection is `full`, run the tests the map does select for the known
paths, print one line naming each unmapped path and saying CI's full run covers it, and run no full
suite. A selection that is `full` with no mapped test at all runs nothing and says so. `make test` with
no arguments still runs everything, for anyone who asks for it. Keep the no-`--run` output (the list,
or `full`) as it is, so CI and other callers see no change.

**Done when:**
- tests/select_tests_test.sh: a branch that changes one mapped file and one unmapped file makes `--run`
  run only the mapped file's tests and print the unmapped path; with the change removed it runs the full
  suite (shown on a worktree copy, quoted in the PR)
- A branch changing only unmapped files makes `--run` run nothing and exit 0, printing that CI covers it
- `select-tests.sh` without `--run` still prints `full` for an unmapped path
- AGENTS.md's "Before you open a PR" block says `--run` never runs the full suite, and CI's run is the gate
- scripts/select-tests.sh --run passes

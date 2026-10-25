---
kind: code
status: ready
depends_on: []
touches: [tests/test_helpers.sh:project setup, bin/swarm.sh:log-finding target file]
estimate_lines: 80
easy: true
---

# Tests never write the project's live .swarm logs

The real .swarm/findings.tsv in swarm-dev's main checkout has a fixture line, `2026-10-25 vacuous-test https://github.com/o/r/pull/9 a line fixed unknown` (line 110), so a test ran `swarm.sh log-finding` against the real project instead of its temp one. That line now counts in `swarm.sh outcomes` and the retro.

Find the test that writes it (grep tests/ for `o/r/pull/9`), and make it run against its own temp project (SWARM_PROJECT, or cd into its mktemp root). The lead removes the fixture line from the real file.

**Done when:**
- A test fails if any test run adds a line to the main checkout's .swarm/findings.tsv or .swarm/events.tsv (compare line counts before and after `make test TESTS=<that test>`), and passes after the fix.

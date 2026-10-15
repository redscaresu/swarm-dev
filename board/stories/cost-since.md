---
kind: code
status: ready
epic: training-export
depends_on: []
touches: [bin/swarm.sh:cost_report, bin/swarm.sh:dispatch (cost arm), bin/swarm.sh:usage header (cost line), tests/cost_test.sh, README.md (:79 cost row), docs/method.md (:219)]
---

# swarm.sh cost takes --since YYYY-MM-DD and refuses an argument it does not understand

cost_report passes its one positional into python as `since`, so `cost --since 2026-10-15` compares dates against '--since' and prints the all-time total (bin/swarm.sh:944-948, dispatch :4233). Validate the way outcomes does (bin/swarm.sh:991-994): accept no argument, `--since YYYY-MM-DD`, and the old positional `YYYY-MM-DD` (tests/cost_test.sh:23 uses it); anything else dies with `usage: swarm.sh cost [--since YYYY-MM-DD]` before reading a log. Dispatch passes "$@". Usage header line (:11), README cost row (README.md:79) and docs/method.md:219 name --since.

**Done when:**
- tests/cost_test.sh: `cost --since 2026-09-15` prints the same table as `cost 2026-09-15`, so the 2026-09-01 agent is left out (total 3 agents, 26.00).
- `cost --since`, `cost --since 2026-9-15`, `cost bogus` and `cost 2026-09-15 extra` each exit non-zero, print the usage line, and print no table.
- The PR shows the refusal checks failing with the validation removed (today `cost bogus` prints the all-time table and exits 0).
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass; humanizer ran over the README/method.md lines and the PR description, and the PR says so.

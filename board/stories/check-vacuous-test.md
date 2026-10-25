---
kind: code
status: ready
depends_on: []
checks: vacuous-test
touches: [scripts/lint:vacuous-test check, tests/lint_test.sh:vacuous-test cases]
estimate_lines: 120
easy: false
---

# A check catches the vacuous tests reviews keep finding

`vacuous-test` was fixed on 4 PRs in the last 30 days and has no check (swarm.sh outcomes, 2026-10-25). The recent cases (.swarm/findings.tsv): a test whose hook input was invalid JSON, so the code it meant to exercise never ran (#515); a docs check that pinned only the opening clause of a rule (#511); a fixture with no line for the case it claimed to cover (#501).

Add a lint check, run by `make check`, for the mechanical form of the first case: a test that feeds JSON to a hook or helper through a heredoc or string must feed JSON that parses (python3 -c 'import json,sys; json.load(sys.stdin)'). Report each failing test file and line. Also add one line to the builder brief's test guidance: a new test must be shown to fail with its fix removed (the falsify step already in the brief), and that step's FAIL line belongs in the PR body.

**Done when:**
- The lint flags a test file with an invalid-JSON hook input and passes a valid one; tests/lint_test.sh covers both, and the flag case goes red if the check is removed.
- `make check` runs it, and it passes on main.

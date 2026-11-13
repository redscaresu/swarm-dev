---
kind: code
status: blocked
epic: flaky-tests
depends_on: [upgrade-skip-closed]
needs: [upgrade-skip-closed (its tests/upgrade_test.sh cases and upgrade_round change; which this test reads)]
touches: [tests/upgrade_test.sh:conductor left case (:518-527)]
estimate_lines: 60
easy: true
---

# upgrade_test's conductor-left case: name the cause and fix it, or hand it to its owner

Needs from upgrade-skip-closed: its upgrade_round change and tests/upgrade_test.sh cases (start from its merged code). upgrade_test 'it is left, never asked' (:518-527, run 40709235861) got '0|0|2' under WAIT_MS=1. Name the cause from the log. If it lies in the test, fix it with a forced red-then-green proof. If it lies in bin/lib/lifecycle.sh's upgrade code, change no bin/ file: add a note naming the line and the cause to the owning merge-mechanics story by board PR (or file a story if that one has merged), and leave the test as it is. next_test's failure (run 40607663207) is a 601 s file TIMEOUT: name it as machine-usable's, out of scope.

**Done when:**
- In the PR (or the board PR), the run is named with its failing check, and the cause is named with its file and line.
- A test cause is fixed with a forced red-then-green proof in a worktree copy, quoted; or a bin/ cause has a note on its owning story or a new story on the board.
- 20 runs of make test TESTS=tests/upgrade_test.sh JOBS=1, one at a time, all green, or the PR says the bin/ cause keeps it red and names the story that owns it.

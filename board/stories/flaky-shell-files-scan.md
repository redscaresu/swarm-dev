---
kind: code
status: ready
epic: flaky-tests
depends_on: []
touches: [tests/timeouts_test.sh:shell_files, tests/timeouts_test.sh:shell files check (:383-384)]
estimate_lines: 50
easy: true
---

# timeouts_test finds every shell file of bin/ and hooks/ on every run

Needs no other story. timeouts_test 'the shell files of bin/ and hooks/ are found' (:383-384) failed the same way twice (runs 40816829991, 40896432254): bin/gh-shim was missing from shell_files' list (:363-371). Find the cause from the logs. Candidates: a `| grep -q` under pipefail at :367 or :384 (it returns 141 on a match once output passes ~64 KB), or something else the log shows. Change the test only with a forced failure that shows the cause: the race forced red in a copy, then green with the fix. If the cause cannot be reproduced, leave the test unchanged, say why in the story's PR, and file a follow-up story by board PR naming what was tried. In the PR, list the other `| grep -q` sites in tests/ (25 files, 46 lines at 2a07799c) for a follow-up.

**Done when:**
- In the PR, both runs are named with their failing check, quoted from the log, and the cause is named.
- If changed: the cause is forced red in a worktree copy without .git and green with the fix; the PR quotes both.
- If the cause cannot be reproduced: tests/timeouts_test.sh is unchanged and a follow-up story is on the board.
- 20 runs of make test TESTS=tests/timeouts_test.sh JOBS=1, one at a time, all green. The count is in the PR.

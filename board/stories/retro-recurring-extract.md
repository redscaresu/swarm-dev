---
kind: code
status: ready
epic: retro-report
depends_on: []
touches: [bin/lib/outcomes_join.py:recurring block, bin/lib/outcomes_join.py:check_story, bin/lib/outcomes_join.py:board_log and board_commits, bin/lib/recurring.py]
estimate_lines: 140
easy: false
---

# Move outcomes' recurring-kinds code into bin/lib/recurring.py, output unchanged

Move the recurring-kinds code out of outcomes_join.py's top level into bin/lib/recurring.py, a module with since, until and min-PR parameters. The code to move: board_log and board_commits (outcomes_join.py:161-178), check_story, finding_day, prs_between and the recurring block (:322-371). outcomes_join.py then imports the module and uses its own RECURRING_MIN_PRS and RECURRING_DAYS (:7-8), so its output does not change. The module makes no gh call. Only outcomes_join's PR meta join uses gh. This exists so retro-recurring-list can share the code instead of copying it.

**Done when:**
- tests/recurring_kinds_test.sh passes with no change to it, under scripts/select-tests.sh --run.
- A worktree copy whose recurring.py drops the 30-day bound fails tests/recurring_kinds_test.sh, and the PR body has the FAIL line.
- python3 -m py_compile bin/lib/*.py passes, and tests/lib_path_test.sh passes: outcomes_join.py imports recurring from bin/lib, never from the working directory.

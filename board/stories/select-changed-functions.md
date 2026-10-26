---
kind: code
status: blocked
epic: test-speed
depends_on: [select-tests-by-file]
needs: [select-tests-by-file: scripts/select_tests.py's changed-file list (committed, uncommitted, untracked) and scripts/select-tests.sh's options]
touches: [scripts/select_tests.py:changed_functions, scripts/select-tests.sh:--functions option, tests/select_tests_test.sh:changed-function cases]
estimate_lines: 170
easy: false
---

# The selector names the bin/ functions and dispatch arms a branch changed

Needs select-tests-by-file's scripts/select_tests.py, its changed-file list and scripts/select-tests.sh. Change-to-function resolution only; the bin rows stay `all`, so selection does not change yet. Map each changed hunk in bin/swarm.sh and bin/lib/*.sh, old side and new, to its enclosing function, or to its arm in bin/swarm.sh's dispatch case. Map a changed bin/lib/*.py to the shell functions that run it, by file name. An untracked new .sh file gives its functions. A line in no function or arm (file top level, a sourced setting) gives `full`. `scripts/select-tests.sh --functions` prints the list, one `file:function` or `file:arm <cmd>` per line, or `full`. 96 of 111 test files run bin/swarm.sh, which sources every bin/lib/*.sh (bin/swarm.sh:437-449), so this is the step that makes narrowing possible (epic Constraints).

**Done when:**
- tests/select_tests_test.sh pins, on fixture commits: an edit inside a function gives that function; an edit to a dispatch arm gives the arm; a deleted function gives its name from the old side; an edit at file top level gives `full`; an edit to a .py gives the shell functions whose bodies name it; a .py no function names gives `full`.

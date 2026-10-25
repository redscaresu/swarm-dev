---
kind: docs
status: blocked
epic: test-speed
depends_on: [select-tests-by-file, suite-cap]
needs: [select-tests-by-file: scripts/select-tests.sh and scripts/select_tests.py, and the --run usage, suite-cap: the cap file path and the slot dir in scripts/test.sh:cap slot]
touches: [AGENTS.md:Before you open a PR, AGENTS.md:Working on this repository tree]
estimate_lines: 25
easy: true
---

# AGENTS.md says run the selector before a push, CI is the gate, and how the suite cap works

Needs select-tests-by-file's scripts/select-tests.sh (its --run usage) and suite-cap's cap file and slot dir. In AGENTS.md's 'Before you open a PR' block (AGENTS.md:130-141): before a push run `scripts/select-tests.sh --run` (the tests mapped to what the branch changed, at JOBS=4; the full suite for a file the map does not know); CI's sharded run (the required test job) is the gate. Add both selector files to the block's shellcheck and py_compile lines (AGENTS.md:134-135) and to the tree's scripts/ line (AGENTS.md:120). Document the machine-wide cap: its file, what a number does, that absent means no cap, and that a nested run skips it. It goes in AGENTS.md, not in CONFIG_KEYS or reference.md's settings table (doc_check_test.sh:63-79). README lines ship with each code story, not here. The plugin's builder brief (bin/lib/build.sh) and commands/ stay unchanged: the selector is swarm-dev's own runner (scripts/test.sh:34). This is the epic's one AGENTS.md story; part-rule-docs depends on it (board_edits). Humanizer over the changed prose; the PR says so.

**Done when:**
- AGENTS.md's 'Before you open a PR' block names `scripts/select-tests.sh --run` as the run before a push and CI's sharded run as the gate, and its shellcheck and py_compile lines include the selector files; AGENTS.md states the cap's file, that absent means no cap, and that a nested run skips it.
- doc_check_test and llms_test pass, and `git diff origin/main --stat -- bin/ commands/` is empty.

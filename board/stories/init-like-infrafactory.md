---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:CONFIG_KEYS block (CFG defaults, CONFIG_KEYS, load_config, show_config), bin/lib/lifecycle.sh:init_project, brief_trailers, bin/lib/build.sh:story_brief, templates/ci/ci.yml (new), templates/pre-commit (new), docs/reference.md:init row, commit_trailers row, README.md:§ quick start init line, tests/init_test.sh, tests/config_test.sh:CONFIG_KEYS]
easy: false
estimate_lines: 230
---

# swarm.sh init writes a board-only CI fast path, a pre-commit check hook and an optional commit_trailers line

Builds on the split: init_project and brief_trailers in bin/lib/lifecycle.sh (bin/swarm.sh:6470-6496, 4187). Today init copies the board templates and adds .gitignore lines. Add three things. When the repo has no .github/workflows, write a ci.yml from templates/: its check job skips its steps when every changed path is under the board, and otherwise runs `make check` (actions pinned by SHA, persist-credentials false, read-only); with workflows present, leave them and print the fast-path step to add. Write a .git/hooks/pre-commit that runs `make check` when the Makefile has a check target; an existing pre-commit hook is left untouched and init prints the line to add. Add a commented `commit_trailers =` line to .claude/swarm/config: a new key, empty by default, and when set, story_brief tells builders to add those trailers to every commit.

**Done when:**
- tests/init_test.sh on an empty git repo: init writes the ci.yml with the board-only skip, the pre-commit hook and the commented commit_trailers line; on a repo with workflows it leaves them and prints the step; on a repo with an existing pre-commit hook the hook stays byte-identical.
- With commit_trailers set, a builder's brief names the trailers and `swarm.sh config` shows the key; tests/config_test.sh accepts it.

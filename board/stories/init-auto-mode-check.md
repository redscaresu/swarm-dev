---
kind: code
status: blocked
epic: merge-agent-setup
depends_on: [init-merge-allow-rule]
needs: [init-merge-allow-rule: init_claude, the init docs lines and init_test's settings stubs (shared parts)]
touches: [bin/lib/lifecycle.sh:init_claude, bin/lib/lifecycle.sh:init_project, bin/swarm.sh:init dispatch arm, bin/swarm.sh:init usage line, tests/init_test.sh:auto mode cases, docs/reference.md:init Claude Code checks, README.md:Getting started init step]
estimate_lines: 120
easy: false
---

# init tells the user to run auto mode's setup, and knows when it was done

Uses init-merge-allow-rule's init_claude (shared part). v0.28.0: the 'Teach auto mode' dialog and permission prompts froze at least six builder panes for hours. init_claude tells the user to run auto mode's environment setup once. Its completion signal: look for a record Claude Code writes when the setup has run (a settings key or file under CLAUDE_CONFIG_DIR) and check it when there is one; in every case `swarm.sh init --auto-mode-done` records the user's own confirmation in .swarm/auto-mode-done (the date), after which init no longer prints the step. Say in the PR which record you found, or that there is none. Document the step and the flag in docs/reference.md, README.md's Getting started and the usage header.

**Done when:**
- tests/init_test.sh gains cases: with no record and no confirmation init prints the step and the --auto-mode-done command; after `swarm.sh init --auto-mode-done` it does not, and .swarm/auto-mode-done holds the date; with Claude Code's record present (when one exists) it does not. Each fails with the check removed.
- init --auto-mode-done writes nothing outside .swarm/ (the test checks the settings files' checksums).

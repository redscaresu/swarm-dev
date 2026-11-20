---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [go-module]
stage: v0.32.0
---

# bin/swarm.sh runs the Go binary for a ported command and the bash for the rest, from one copy of what runs around every command

Tests and checkouts run a binary built from the tree.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) With the binary variable set the wrapper runs that binary and makes no download or build. `make test` builds once and sets it, and a copy of the tree with no .git and broken Go goes red under `make test`. (2) A git checkout builds from source into the ignored path, and builds again when a Go file is newer than the binary: a test edits a .go file and sees the new behaviour on the next call. (3) A command with no marker file runs the bash with the same output and exit code as before the epic. A fixture command with a marker runs the binary from the frame's dispatch with the project, board and settings the frame resolved, and its failure line and exit code reach events.tsv as a bash command's do. (4) Markers are per dispatch name, `_` names included. A fixture command with two forms, one in Go and one still bash behind a `_` name, runs each form with the right arguments, usage errors and exit codes, and bash calls a `_` entry of the binary the same way. (5) A find-only entry for hooks finds the binary or says there is none, and never downloads or builds, shown with gh and go stubs that fail on any call. (6) doc_check and skill_test still find the full count of commands and settings on the wrapper tree, and each fails when it finds none. (7) SWARM_FORBID_PROJECT is refused before the binary runs, and the version is read from plugin.json with no python3 on PATH. (8) An agent started while the binary variable is exported does not get it: a test reads the agent's environment.

**Out of scope:**
- Download, checksum, attestation and the fallback build on an installed copy (binary-fetch)
- Hook and gh-shim wrappers (port-guard, port-hooks)
- The release workflow (release-ci)
- Moving the frame to Go (port-frame)
- Windows

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/command_names_test.sh, tests/config_test.sh, tests/doc_check_test.sh, tests/events_test.sh, tests/port_names_test.sh, tests/skill_test.sh. Each keeps the assertion its go_check column names.
- stage: v0.32.0. The wrapper runs on bash 3.2 and passes shellcheck.
- While any command is bash, bin/swarm.sh keeps the one copy of what runs around every command: the project lookup, the SWARM_FORBID_PROJECT refusal (bin/swarm.sh:201-211), the shim on PATH (:229-233), the workspace label, the settings and the outcome line (main, :1287). A ported command's arm in main moves to Go with its port. The frame itself moves in port-frame. The HLD's three exceptions do not cover a second copy of the frame: contradiction 15.
- One marker file per ported command, so two port PRs never edit the same line (HLD:182-183). No marker routes by flag: the first port of a command with several forms (wait, merge) takes the name and hands a form still in bash to a `_` name.
- The binary variable is not handed to agents: it has no SWARM_ prefix, or agent starts drop it (AGENT_PREFIXES, bin/lib/agents.sh:388-392). scripts/test.sh and tests/test_helpers.sh unset every SWARM_* but two (scripts/test.sh:45-60; tests/test_helpers.sh:25-27), so it is set after that or exempted.
- doc_check and skill_test read the commands and CONFIG_KEYS from bin/swarm.sh's text (tests/doc_check_test.sh:23-31; bin/swarm.sh:262).
- `version` and `update` run before any project is looked for (bin/swarm.sh:159-162) and keep working.
- `make test` builds once and sets the variable: the root Makefile and scripts/test.sh change.

**Your part:**
- You merge the PR that changes the root Makefile (protected path).
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.

**Areas:**
- bin/swarm.sh (dispatch, main, marker lookup, plugin_version)
- bin/ (marker files)
- Makefile
- scripts/test.sh
- tests/test_helpers.sh
- tests/
- .gitignore
- AGENTS.md (pre-PR commands)

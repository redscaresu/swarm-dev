---
kind: chore
status: ready
epic: agent-state-from-the-session
depends_on: []
touches: [tests/claude_stub.sh (new), tests/config_test.sh (stub checks), tests/epic_test.sh (PATH setup), tests/review_test.sh (PATH setup), tests/events_test.sh (PATH setup), tests/next_test.sh (PATH setup), tests/dash_test.sh (PATH setup)]
---

# A shared `claude` stub for the tests

Add tests/claude_stub.sh. It is not named *_test.sh, so CI's glob does not run it, but shellcheck covers it through tests/*.sh (survey; .github/workflows/ci.yml:23,33). `--version` prints $CLAUDE_STUB_VERSION, default `2.1.296 (Claude Code)`. `agents --json` prints the file $CLAUDE_STUB_AGENTS names, or `[]` when unset. Any other call exits 1 and names the call. Copy the fixture's shape (top-level form, sessionId, status, waitingFor, name, cwd, kind, startedAt, pid) from one entry of the installed binary's `claude agents --json`, with ids and paths replaced. Put the stub on PATH as `claude` in config_test, epic_test, review_test, events_test, next_test and dash_test (each already isolates CLAUDE_CONFIG_DIR, e.g. tests/epic_test.sh:13). Each reader story rewrites that test's herdr-state fixtures. No change to bin/swarm.sh.

**Done when:** config_test checks that the stub prints the version, prints a fixture it wrote, prints `[]` with none, and exits non-zero on `claude foo`; removing the stub from PATH fails those checks. The other five tests pass with it on PATH. shellcheck passes on tests/*.sh. The PR body shows the real entry the fixture came from, with ids and paths replaced.

**From review (binding; overrides the scope above where they differ):**
- config_test checks the version with CLAUDE_STUB_VERSION set to a value the real binary never prints (e.g. `0.0.1 (Claude Code)`) and asserts the exact string, so a real `claude` on a dev box cannot pass it.
- Put the stub in its own directory and prepend it to the exported PATH at the top of each of the six tests, so every per-run PATH (nobin, slowgh, badpy, size, REALPATH, next_test's per-scenario bin) sees the stub and never the real claude. Drop the claim that each test isolates CLAUDE_CONFIG_DIR, or add the export to dash_test and next_test.
- Copy the fixture shape only from fields a real entry has (a top-level JSON array of entries with cwd, kind, name, pid, sessionId, startedAt, status). Mark `waitingFor` unverified in the stub and the PR body until a real waiting entry is captured (pin-claude-version can capture one).

---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/codex_test.sh, tests/board_state_test.sh, .github/workflows/ci.yml]
---

# The test suite passes on ubuntu-26.04

ubuntu-latest became ubuntu-26.04 on 2026-10-19 and main went red at 21c48ac. Its Rust (uutils)
coreutils refuse a tool run under another name, so codex_test's `ln -s "$(command -v sleep)"
stubsleep` (tests/codex_test.sh:18) fails with "Requested utility `stubsleep` does not match
executable name". board_state_test's "two writers to w at once" also failed in that run. CI is pinned
to ubuntu-24.04 meanwhile (fix PR #321).

Make the stub a shell script named stubsleep that execs sleep (so pgrep -f still finds the name), check
board_state_test's two-writer case on 26.04 (flock and mktemp behaviour), then move ci.yml back to
ubuntu-latest.

**Done when:**
- ci.yml runs on ubuntu-latest (26.04) and every test job is green on this PR.
- `grep -rn 'ln -s.*command -v' tests/` finds no symlinked coreutils stub.

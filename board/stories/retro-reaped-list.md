---
kind: code
status: blocked
epic: retro-report
depends_on: [retro-command]
needs: [retro-command (the section runner and its context (window day; events.tsv path))]
touches: [bin/lib/retro_reaped.py, tests/retro_reaped_test.sh, docs/reference-logs.md:reaped paragraph (swarm.sh retro part)]
estimate_lines: 80
easy: true
---

# retro's reaped list: the load the swarm had to kill since the tag

Needs from retro-command: the section runner and its context (window day, events.tsv path). Add bin/lib/retro_reaped.py. It prints every `reap` events line since the window's day, as local day, target, outcome, and the slug= and role= fields when present. Then it prints a count per target. Two places write reap lines. scripts/test.sh:113-115 writes a test file's `TIMEOUT after <n>s` into TEST_REAP_LOG (:65), the events.tsv beside the run's test-runs.tsv. codex_review (bin/swarm.sh:860, :943) writes `timed out after <N> min` with a codex-<x> target. A fallback reviewer killed on its timeout writes no reap line. The section says so under its rows, so a short list is not read as no load (rules.md:15). If nothing is found, print a line saying so. Docs: fill only the **reaped** stub paragraph that retro-command wrote in docs/reference-logs.md's `### swarm.sh retro` part, and leave the other paragraphs alone. docs/reference-logs.md:87-94 already documents the lines themselves.

**Done when:**
- tests/retro_reaped_test.sh (new) uses a fixture events.tsv with a test-file reap line and a codex reap line since the tag, and one reap line before it. `swarm.sh retro` prints the first two with their targets and outcomes, leaves out the third, and prints the line about fallback reviewers.
- The new test fails on a worktree copy that drops the window filter, and the PR body has the FAIL lines. scripts/select-tests.sh --run passes.

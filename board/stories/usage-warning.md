---
kind: code
status: ready
epic: handover-usage
depends_on: []
touches: [bin/lib/usage_estimate.py (new), bin/lib/lifecycle.sh:wait --lead usage warning, bin/swarm.sh:CONFIG_KEYS usage_warn_percent, bin/swarm.sh:config defaults usage_warn_percent, docs/method.md:settings table usage_warn_percent row, README.md:usage estimate line, tests/usage_estimate_test.sh (new), tests/config_test.sh:usage_warn_percent default, tests/wait_lead_test.sh:usage warning cases]
estimate_lines: 200
easy: false
---

# wait --lead warns once when the usage estimate passes a threshold the user sets

Split out of handover-and-usage. A usage estimate: price-weighted tokens since the weekly reset, read from `~/.claude/projects/**/*.jsonl`, calibrated against a `/usage` reading the user gives. Fable is weighted separately: on 2026-10-25 a single weighting read 90.6% while /usage showed 95%, because Fable's share was underweighted.

Add `usage_warn_percent` to CONFIG_KEYS, validated as a whole number from 1 to 100, empty (off) by default, so merging this changes no behaviour. With it set, `wait --lead` prints one `usage:` line the first time the estimate passes it in a usage week, and not again that week. Add the setting's row to docs/method.md's settings table (§ Configuring a project), and one README line. Both say this is an estimate, that it undercounts Fable when uncalibrated, and that `/usage` is the only truth. It is a warning, never a gate: nothing stops or slows on it.

Read only these fields of each jsonl line: `message.usage`, `message.model` and the line's timestamp. Never read conversation content. Tests use fixture jsonl under a stand-in CLAUDE_PROJECTS_DIR and never read the real `~/.claude/projects`.

**Done when:**
- tests/usage_estimate_test.sh: fixture jsonl with Fable and Opus usage gives the two calibrated shares the test pins, and Fable's weight differs from Opus's
- tests/wait_lead_test.sh: with `usage_warn_percent` set below the fixture's estimate, one `usage:` line prints; a second poll in the same week prints none; with the key unset, no line prints
- tests/config_test.sh: the key defaults to empty, and 0, 101 and a non-number are refused naming the line
- The once-per-week case goes red with its seen-check removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- doc_check_test passes with the new settings row
- scripts/select-tests.sh --run passes

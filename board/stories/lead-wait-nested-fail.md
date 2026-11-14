---
kind: code
status: ready
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_queue, bin/lib/lifecycle.sh:wait_lead traps, tests/wait_lead_test.sh:nested read and signal cases]
estimate_lines: 120
easy: false
---

# wait --lead fails loudly on a failed queue read and on INT or HUP

A post-merge codex pass on #834 (lead-wait-timeout-line) found two gaps in its promise that wait --lead prints a line on every exit.

1. A failed nested read is swallowed. An unreadable story state makes state_value call die inside `held="$(get_fm ...)"` in lead_queue (bin/lib/lifecycle.sh:3106 onward), but lead_queue carries on and returns 0. So the poll accepts an incomplete queue, overwrites LEAD_SEEN, and can report a timeout instead of `wait-failed:`. #834's test misses it because it replaces the whole queue function with `return 7`.
2. Only TERM and USR1 are trapped. On bash 3.2 an unhandled INT or HUP skips the EXIT trap, so the wait exits 130 or 129 with no line and leaves its PID file.

Propagate a failed nested read out of lead_queue, and trap INT and HUP through the same cleanup, exiting 130 and 129.

**Done when:**
- A case with a real, unreadable story state (not a stubbed lead_queue) prints `wait-failed:`, exits non-zero and leaves `seen` as it was
- Cases sending INT and HUP to a running wait --lead each print its exit line, exit 130 and 129, and leave no PID file
- Each case goes red with its fix removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- scripts/select-tests.sh --run passes

---
kind: code
status: blocked
checks: unhandled-state
depends_on: [check-docs-misstate-code]
needs: bin/lib/build.sh review_checklist, after check-docs-misstate-code's line
touches: [bin/lib/build.sh:review_checklist, tests/review_checklist_test.sh, tests/timeouts_test.sh (new)]
estimate_lines: 80
easy: true
---

# The review and a lint catch an external call with no timeout and a state with no exit

`unhandled-state` recurs in 53 PRs in 30 days, with no check (`swarm.sh outcomes`, 2026-10-23). Recent instances: the detached CI refresh had no timeout and stacked; a log download had no timeout and blocked reconcile; a queue-wait timeout left a PR queued with nothing reconciling it; two concurrent watches double-counted a red head; an exact-equality threshold never fired again after one miss.

- Add one line to review_checklist (bin/lib/build.sh:703): for every new wait, external call (gh, herdr, curl, a download) and status the diff adds, name its timeout, what happens when it fails or times out, what clears it, and what a second concurrent run does. A missing answer is a finding.
- Add tests/timeouts_test.sh, run by `make test`: in bin/ and hooks/, a `gh run download`, `gh run view --log`, `curl` or `herdr ... --wait` with no `timeout`/`--max-time`/`--timeout` on the same line fails, unless the line ends `# no-timeout: <reason>`. Lines that hit today get the comment with a reason, or are fixed if the fix is one line.

**Done when:**
- tests/timeouts_test.sh fails on a fixture with a bare `curl` and a bare `gh run download`, and passes with `--max-time`/`timeout` or the opt-out comment; it passes on main.
- A test checks that review_checklist's output holds the new line.
- `make test` passes.

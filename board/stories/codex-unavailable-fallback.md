---
kind: code
status: blocked
epic: reliable-runs
depends_on: [codex-rate-limit-retry]
needs: [codex-rate-limit-retry (shares bin/swarm.sh:codex_review; build on its retry branch and its tests)]
touches: [bin/swarm.sh:codex_review (timeout and unreachable branches), bin/swarm.sh:codex_limit, tests/codex_unavailable_test.sh, docs/reference-building.md:codex-review paragraph (§ Building)]
estimate_lines: 160
easy: false
---

# A codex that times out or cannot connect hands its review to the fallback reviewer

On 2026-11-12/13 codex's provider (an Azure Foundry endpoint) shut down. For about 10 hours every `swarm.sh codex-review` printed `Reconnecting... waiting for network` until codex_minutes ran out, then `codex skipped: timed out after 10 min`, and nobody reviewed in codex's place. codex_review (bin/swarm.sh:869-945) runs codex_fallback only on a usage or rate limit (CODEX_LIMIT_KIND, :929-939). On a timeout it records a `reap` event and dies (:942-944), and by then `left` is 0 (:921), so a fallback would get no time anyway.

Builds on codex-rate-limit-retry's retry branch in codex_review; keep its behaviour and tests as they are.

Two changes, both "codex could not review":
1. Unreachable: while codex runs, read its log. When it holds 3 or more `Reconnecting...` lines with no review output since, or a `stream disconnected before completion` line, stop codex at once, record `incident codex-<story> "codex-unreachable"`, and treat it like a limit: with fallback_reviewer set, run codex_fallback. Match the lines with a named regex beside CODEX_LIMIT_RE, as codex_limit does.
2. Timed out: with fallback_reviewer set, run codex_fallback after the `reap` event, with a fresh budget of codex_minutes, instead of the `left` that is now 0. With fallback_reviewer empty, keep today's `codex skipped: timed out` exit.

The fallback's own line stays `reviewed by fallback <model>: codex <kind>`, with kind `unreachable` or `timeout`.

**Done when:**
- tests/codex_unavailable_test.sh: a codex stub that prints `ERROR: Reconnecting... 1/5` three times and then hangs is stopped within 30 s (SWARM_CODEX_SECONDS set high, so a timeout cannot be what stops it), an `incident` line with `codex-unreachable` is in events.tsv, and with fallback_reviewer set the fallback reviews; with it empty, codex-review exits non-zero printing `codex skipped: unreachable`
- A stub that prints `stream disconnected before completion` once is handled the same way
- A stub that hangs silently past SWARM_CODEX_SECONDS: with fallback_reviewer set, the fallback runs and gets a full codex_minutes budget (assert the budget it was passed, not the wall time); with it empty, today's `codex skipped: timed out` line and exit stay
- A stub that prints one `Reconnecting...` line and then a normal review is not stopped, and no incident is recorded
- Each new case goes red with its branch removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- tests/codex_test.sh, tests/codex_rate_limit_test.sh and tests/fallback_reviewer_test.sh still pass
- docs/reference-building.md's codex-review paragraph says a timeout or an unreachable codex runs the fallback reviewer
- scripts/select-tests.sh --run passes

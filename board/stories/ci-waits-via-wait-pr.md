---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:builder and conductor briefs, bin/lib/merge.sh:wait_pr, hooks/merge-guard.sh, tests/]
---

# Every CI wait goes through wait-pr, and wait-pr names a conflict

On 2026-10-18 plan-epic-child-epics (#271) sat 6.5 hours in a hand-written `gh pr checks` loop on
a head with a red check, and merge-admin (#281) sat in one on a PR that conflicted with main and so
had no checks. wait-pr (#275) exits on red, on no checks and on a deadline, but no brief tells an
agent to use it, so agents write their own loops.

- The builder and conductor briefs say: wait on a PR's CI only with `swarm.sh wait-pr <PR URL>`,
  never a loop of your own; on exit 1 fix the red check, on a conflict merge main in.
- wait_pr reads the PR's mergeable state before polling checks. A PR that conflicts with its base
  exits 2 at once with `conflicts with <base>: merge <base> in, then push`, not after the 5-minute
  no-checks grace. GitHub's `UNKNOWN` mergeable state (still computing) is polled, not treated as a
  conflict.
- With `SWARM_AGENT` set, hooks/merge-guard.sh blocks `gh pr checks --watch` and a shell loop
  around `gh pr checks` (`until`/`while` on it), naming `swarm.sh wait-pr` instead. A single
  `gh pr checks` call stays allowed.

**Done when:**
- A stub PR with mergeable CONFLICTING makes wait-pr exit 2 within one read, printing the conflict line; UNKNOWN then MERGEABLE goes on to poll checks.
- The rendered builder and conductor briefs contain the wait-pr rule (a test greps both).
- With SWARM_AGENT set the hook blocks `gh pr checks 271 --watch` and `until gh pr checks 271; do sleep 30; done`, and allows `gh pr checks 271`; without SWARM_AGENT it allows all three.

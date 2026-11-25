---
kind: code
status: ready
fix: true
depends_on: []
touches: [bin/lib/merge.sh:wait_pr, bin/lib/ci_gate.py:head mode, tests/wait_pr_test.sh]
estimate_lines: 150
easy: false
---

# Make wait-pr back off while a PR's checks are only queued

On 2026-11-24 the GitHub REST budget ran out (0 of 5000, 16:43Z) with 16 story PRs open and 39 Actions runs queued behind the free plan's runner limit.
.swarm/gh-calls.tsv shows `swarm.sh wait-pr` made 2917 of about 4,800 logged calls in the hour before; `watch` made 614 and `merge` 552.
Its calls were three reads per poll, almost evenly: commits/:sha/check-runs (791), commits/:sha/status (781) and actions/runs?head_sha (769) (bin/lib/ci_gate.py:715-718, :664).
wait_pr polls every MERGE_POLL = 20 s (bin/lib/merge.sh:4, the loop at :2572-2689), so one waiter costs about 9 calls a minute, and 16 waiters about 144 a minute (8,600 an hour), whatever the checks are doing.
The poll cache (bin/lib/merge.sh:2563-2571) shares reads only between waits on the same head, and each story PR has its own head, so it saves nothing here.
While every pending check is queued (no runner yet), nothing can change faster than a runner picks one up, which on a busy day takes minutes.

Change wait_pr, and ci_gate's head mode where it must report it, so that:
- When every pending check run and workflow run on the head is `queued` (none `in_progress`), the next poll comes after a longer pause that doubles each such poll, from MERGE_POLL up to a cap of 120 s (a module constant, overridable by a SWARM_ setting for tests). The pause drops back to MERGE_POLL as soon as any check is `in_progress` or any finishes.
- A finished red check still ends the wait on the very next poll, as today: back-off never delays a red or green end by more than one poll at the current pause.
- --timeout, the no-check grace and the rate-limit wait keep their meanings; a back-off pause never runs past the deadline.
- Add the new setting's row to docs/port/ and the SWARM_ list the port checks read, and say in docs/reference-merging.md § wait-pr how the pause grows, one sentence per line.

**Done when:**
- A test in tests/wait_pr_test.sh runs wait-pr against a stubbed gh whose checks stay `queued` for 10 polls and then go green, with MERGE_POLL and the cap set small. It counts the stub's gh calls, and fails if the calls made while queued exceed those of a fixed back-off schedule (doubling to the cap). It passes on the fix and fails with the back-off removed (shown on a worktree copy).
- The same test, with one check moving to `in_progress` and then red mid-run, ends red within one MERGE_POLL of the red read.
- Existing wait_pr tests (wait_pr_test.sh, wait_pr_cache_test.sh, wait_pr_expected_test.sh, wait_pr_new_head_test.sh) pass unchanged.

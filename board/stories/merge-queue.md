---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:merge, bin/lib/build.sh:conductor brief, .github/workflows/ci.yml, docs/reference.md, docs/method.md:Building, tests/]
---

# swarm.sh merge goes through GitHub's merge queue where a repo has one

Two PRs green on their own broke main together on 2026-10-18 (#293 with #287's era of next_test.sh),
because each PR's CI ran on an older main. GitHub's merge queue tests each PR on top of current main
and the PRs queued ahead of it, and merges groups at once, so a red combination never lands and
merges stop waiting one main-CI run each.

- ci.yml runs on `merge_group` as well as `pull_request` and `push`.
- `swarm.sh merge` detects a queue on the base (the ruleset's merge_queue rule, REST) and then
  enqueues the pinned head (`gh pr merge --auto` with `--match-head-commit`) and waits for the PR to
  be merged or dequeued, instead of merging and waiting on main's CI. A dequeue prints the failing
  checks and exits non-zero. Without a queue, behaviour is unchanged.
- A dequeued PR is handled like a red check: the conductor brief sends the failing check to the builder, which merges main in and pushes. docs/method.md § Building and docs/reference.md describe the queue path.
- infrafactory keeps no queue: its ruleset needs an approving review and merge-admin merges with --admin, which skips a queue. Say so in docs/reference.md.
- Turning the queue on for swarm-dev is the lead story merge-queue-on, not this PR.

**Done when:**
- ci.yml has a `merge_group` trigger, and actionlint passes.
- With a stubbed ruleset that has merge_queue, `merge` enqueues with the pinned head and reports a stubbed dequeue as a failure naming the check; with no merge_queue rule it takes today's path (existing merge tests pass unchanged).

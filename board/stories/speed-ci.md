---
kind: code
status: blocked
epic: port-checks
depends_on: [speed-run, protected-go-paths, docs-gate-go, patch-gate-port]
needs: speed-run (tests/speed_run.sh and --require-count); protected-go-paths, docs-gate-go, patch-gate-port (merged first, so the new job never runs on their open PRs)
touches: [.github/workflows/speed.yml, AGENTS.md:speed job paragraph (Working on this repository)]
estimate_lines: 100
---

# CI runs the speed run on each PR, with the process counter installed

Uses speed-run's script and --require-count. New .github/workflows/speed.yml on pull_request, base against head: the board-only gate copied from ci.yml:29-39, pinned actions, read-only permissions, persist-credentials: false. One step installs the counter speed_run.sh names, since the runner image does not promise strace; the run then uses --require-count. A self-check step runs a copy of the head with one extra external exec in one listed command, and fails unless that command shows exactly one more process start. workflow_dispatch takes a base ref input, through env, for an exit. It waits for ship-gates' three PRs for the same reason as diff-run-ci. AGENTS.md gains a paragraph on the speed job, tests/speed_list.txt and how a port epic adds its commands. The PR changes .github/, so merge's protected-path hold hands it to the user.

**Done when:**
- (1) The speed job runs on this PR and prints a row per listed command, with both trees' median wall time and a number of process starts, never `not measured`. (2) Its self-check step passes on this PR. (3) zizmor passes on the file, and a board-only PR skips the job's steps.
- scripts/select-tests.sh --run passes

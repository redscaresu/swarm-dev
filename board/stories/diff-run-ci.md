---
kind: code
status: blocked
epic: port-checks
depends_on: [allow-list, diff-run-order, diff-merge-fixtures, protected-go-paths, docs-gate-go, patch-gate-port]
needs: allow-list (the lists --base reads); diff-run-order (--times for the ten-run step); diff-merge-fixtures (the merge fixtures that step runs); protected-go-paths, docs-gate-go, patch-gate-port (merged first, so the new job never runs on their open PRs)
touches: [tests/diff_run.sh:base option, .github/workflows/diff-run.yml, tests/diff_base_test.sh, AGENTS.md:differential run paragraph (Working on this repository)]
estimate_lines: 230
---

# Each PR's CI runs the differential run against its base

Uses diff-run-core's run, allow-list's lists, diff-run-order's --times and diff-merge-fixtures' fixtures. `--base` applies only the entry of the head's own story (branch story/<slug>, so scripts/allow/stage-*/<slug>.md). Other stories' entries, on the base or added by the head as the allow-* stories add theirs, are left to --stage. So a PR that changes output passes only with its own entry, and a port PR passes only with no difference. New .github/workflows/diff-run.yml on pull_request and merge_group: the board-only gate copied from ci.yml:29-39, a worktree of the base SHA, then `tests/diff_run.sh --base <base> <head>`. A second step runs `--times 10`, head against head, over the merge fixtures. That is the ten-run check of the epic's Done when (3), run in CI, not on the lead's machine. workflow_dispatch with a stage input runs `--stage <n>` from the v0.31.2 tag, for an exit. Checkout pinned as ci.yml:25, persist-credentials: false, contents: read; the input reaches run: through env. No push trigger, so it is no part of main's CI check (bin/lib/merge.sh:84). It waits for ship-gates' three PRs. Once on main, it runs on every open PR that merge brings up to date, and protected-go-paths' usage line would be red on its own PR, which has no entry. AGENTS.md gains a paragraph: tests/diff_run.sh, where fixtures go, scripts/allow/stage-<n>/<slug>.md, and that a PR changing output on purpose adds its entry (P14). The PR changes .github/, so merge's protected-path hold hands it to the user.

For a `merge_group` run the head is a synthetic `gh-readonly-queue/...` ref holding several story PRs. Select the allow-list entries of every story PR in the group (from the group's PR list), not of one head story, so a queued PR that changes output on purpose and passed its own differential check also passes the queue check (codex).

**Done when:**
- (1) On this PR's head the job passes, its log names each fixture compared, and the ten-run step passes; the PR quotes its wall time. (2) Locally, the job's command on a copy of the head with one byte of a seed fixture's output changed fails, and passes once the head's story has an entry for it. (3) tests/diff_base_test.sh, with the head on story/a: a difference covered by a's entry passes; one covered only by b's entry, on the base or added by the head, is red; b's entry added by the head with no difference behind it is not red. (4) zizmor passes on the file, and a board-only PR skips the job's steps. (5) Locally, the dispatch step's command, `--stage 1` from v0.31.2, runs and lists each difference; the PR quotes the result.
- scripts/select-tests.sh --run passes
- A merge-group fixture holding two story PRs with allow-list entries passes; with one entry removed it fails, naming that PR's change

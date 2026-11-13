---
kind: code
status: ready
depends_on: []
touches: [bin/lib/board.sh:review head CI check (ci_gate.py head call), tests/review_test.sh:expected-workflow case]
estimate_lines: 60
easy: true
---

# A review's new-head CI check waits for every expected workflow, as wait-pr does

A post-merge codex pass on #861 (review-accepts-base-merge) found this. The CI check that accepts a reviewed head plus clean base merges calls `ci_gate.py head <repo> <head>` (bin/lib/board.sh:2799) without the `<base> <pr> <changedFiles>` arguments that wait-pr passes. Without them ci_gate skips its expected-workflow check. So if one check succeeds while another `pull_request` workflow that applies to the PR has not started, the call returns 0 and the head is accepted with CI incomplete. Codex reproduced it with mocked responses: with the arguments the same call returns 2 with `(no run on ...)`.

Read the PR's base, number and changedFiles there, as wait-pr does, and pass them.

**Done when:**
- tests/review_test.sh (or the file that tests this check today) has a case: one check green and an expected workflow with no run on the head. The head is not accepted, and the output names the workflow with `no run on`
- That case goes red with the arguments taken out again, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- An all-green head with every expected workflow run is still accepted
- scripts/select-tests.sh --run passes

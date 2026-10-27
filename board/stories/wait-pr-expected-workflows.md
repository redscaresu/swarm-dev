---
kind: code
status: ready
epic: merge-holds
depends_on: []
touches: [bin/lib/ci_gate.py:head mode, bin/lib/ci_gate.py:push_filters, bin/lib/merge.sh:wait_pr, docs/reference.md:wait-pr row, tests/wait_pr_expected_test.sh (new)]
estimate_lines: 190
easy: false
---

# wait-pr counts a workflow that should run on the head but has not started yet as pending

Cause 2 of HLD Appendix C (board/hld/2026-10-25-swarm-dev-0-28.md:868-871). ci_gate head (ci_gate.py:673) calls a head green once it has at least one check and every check passed. It does not know which workflows should run, so one fast check, green before the test shards are created, reads as green. Only main_ci asks expected() (ci_gate.py:471, :551), and expected() reads push triggers only (push_filters, :365).
- ci_gate head takes optional <base> <pr> <changed>. With them, it reads the workflows at the head that a pull_request into <base> with the PR's files triggers (branches and paths filters, the same parser as push_filters made to read pull_request too). Each such workflow with no run on the head is pending, named in the line.
- Without the extra args, ci_gate head behaves as today. Its other callers stay unchanged: merge_pr (merge.sh:293) pins a head that already passed wait-pr, and lead_heads and ci_red_scan read heads that were already waited on.
- A workflow whose triggers cannot be read is not waited on, and the line says so. That falls back to today's behaviour rather than blocking.
- wait_pr (merge.sh:967) reads changedFiles in its head read and passes base, PR and count. An expected workflow still with no run WAIT_PR_GRACE after the first read ends the wait with exit 2, naming it, as `no check runs` does.
- Docs: reference.md's wait-pr row (:2374) and the green rule's description say an expected workflow that has not started counts as pending.
- Order across epics: review-loop's owner-waits-green also edits merge.sh:wait_pr. If both are open, this merges first: it adds one read field and the call's arguments.

**Done when:**
- tests/wait_pr_expected_test.sh (new): the head has .github/workflows/ci.yml (on: pull_request) and gitleaks.yml. Only gitleaks' run and check exist, green. wait-pr prints pending naming ci.yml and does not exit 0. Once the stub adds ci.yml's run and its shard checks, all green, it exits 0.
- Same file: a workflow whose pull_request paths filter misses every file the PR changes is not waited on. A workflow whose triggers cannot be read is not waited on and is named in the output. An expected workflow that never starts ends the wait with exit 2 after SWARM_WAIT_PR_GRACE, naming it.
- Same file: `ci_gate head <repo> <sha>` with no extra args gives today's verdict for the gitleaks-only head (green).
- tests/wait_pr_test.sh passes unchanged.
- The PR body says the gitleaks-only case exited 0 on main's ci_gate in a copy of the checkout.
- reference.md's wait-pr row says an expected workflow that has not started counts as pending.

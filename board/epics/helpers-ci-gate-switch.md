---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit, helpers-ci-gate-core, helpers-ci-gate-cache, helpers-ci-gate-modes, helpers-ci-gate-main, helpers-ci-gate-prep]
---

# Every ci_gate caller runs the binary, and ci_gate.py and poll_cache.py are gone

One story switches every bash entry to the binary and deletes both Python files. The lead story after it checks CI's board-only gate on the next PR.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** bin/lib/ci_gate.py and bin/lib/poll_cache.py are gone, and no file under bin/ or scripts/ names either. The differential run is clean for the merge, wait-pr, review-agent, status and next fixtures. CI's board-only gate gives the same verdict on every case of tests/board_only_test.sh, the version-only release fast path among them, on the PR that deletes ci_gate.py and on the first PR after it.

**Stories:**
- [ci-gate-switch](../stories/ci-gate-switch.md)
- [ci-gate-after-switch](../stories/ci-gate-after-switch.md)

**Out of scope:**
- Porting merge or wait-pr as commands (port-merge, port-wait-pr)
- Porting scripts/board-only.sh itself

**Your part:**
- You merge ci-gate-switch (protected merge package). The carve-out covers it, as in the parent.
- Lead: ci-gate-after-switch, and shared step L2: cut the patch that carries the switch to the prerelease ref.

**Areas:**
- ci-gate-switch: [bin/lib/ci_gate.py, bin/lib/poll_cache.py, bin/lib/merge.sh:file head constants, bin/lib/merge.sh:ci_gate, bin/lib/merge.sh:pr_contents, bin/lib/merge.sh:pinned_files, bin/lib/merge.sh:base_moved, bin/lib/merge.sh:merge_base_update, bin/lib/merge.sh:board_paths, bin/lib/merge.sh:clear_red_main, bin/lib/merge.sh:queue_merge, bin/lib/merge.sh:wait_pr, bin/lib/merge.sh:watch_prs, bin/lib/merge.sh:watch_gh, bin/lib/lifecycle.sh:heads_green, bin/lib/lifecycle.sh:lead_bases, bin/lib/lifecycle.sh:main_red_run, bin/lib/board.sh:next_queued, bin/lib/board.sh:review_heads, bin/lib/build.sh:review_recheck, scripts/board-only.sh:version-only path, scripts/board-only.sh:header, tests/ci_gate_cases_test.sh:python side, tests/board_only_test.sh:gate step cases, tests/merge_queue_test.sh:queued handler case, tests/merge_ci_budget_test.sh:simulated wait, tests/merge_ci_budget_test.sh:spy, tests/merge_base_moved_test.sh:on_board cases (py_on), tests/merge_rules_test.sh:file read that dies silent, tests/watch_cache_test.sh:header, tests/wait_pr_cache_test.sh:header, tests/wait_pr_cache_test.sh:contracts left direct, tests/poll_cache_lock_test.sh:python side, tests/diff_run.sh:SIGQUIT comment, tests/diff_run_order_test.sh:SIGINT comment, tests/diff_fixtures_ci_gate.sh:nopy fixtures, tests/nopy_list.txt:ci_gate lines, docs/reference-logs.md:poll cache, docs/port/locks.tsv:.swarm/poll-cache rows, docs/port/swarm-names.tsv:SWARM_POLL_CACHE, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_AGE, docs/port/swarm-names.tsv:SWARM_POLL_CACHE_SECONDS, docs/port/tests.tsv:tests/poll_cache_lock_test.sh row, scripts/allow/stage-2/ci-gate-switch.md]
- ci-gate-after-switch: []

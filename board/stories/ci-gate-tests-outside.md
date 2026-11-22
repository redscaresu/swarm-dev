---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [tests/wait_pr_cache_test.sh:python3 wrapper, ps match and direct head runs, tests/wait_pr_expected_test.sh:direct head run, tests/board_only_test.sh:fixture (main's base0 files), tests/merge_base_moved_test.sh:on_board cases, tests/merge_ci_budget_test.sh:wait records folder, tests/merge_rules_test.sh:file read that dies silent]
estimate_lines: 290
---

# Tests-only: the tests that run, copy or stub ci_gate.py by name drive swarm.sh and the gate from outside

P2's tests-only PR. It rewrites the py and python3-stub reaches of docs/port/tests.tsv rows 28, 89, 93, 150 and 151, and merge_rules_test.sh's ci_gate case (row 101 is helpers-shared's, whose plan does not touch that case: contradiction 12). Their lib reaches are port-merge's and stay.
- wait_pr_cache_test.sh: the python3 wrapper (:70-75) counted each waiter's head passes. The rewrite counts each waiter's polls from the gh stub's `pr view` calls, logged with WAITER: wait-pr reads the PR before every head pass, cache hit or not (merge.sh:2579). The ps match on ci_gate.py (:48) finds the reading process without naming ci_gate.py or the binary. The direct head runs (:125, :240) become `swarm.sh wait-pr` runs whose settings give the same contracts: cache off (WAIT_PR_FRESH, merge.sh:2564), a max age of 0, and a rejected read (the short fixture) that is not kept. A contract that cannot be reached that way stays direct, and the PR names it; the switch moves it to the binary.
- wait_pr_expected_test.sh:212: the direct head run becomes `swarm.sh wait-pr` on the same fixture.
- board_only_test.sh:49: the fixture copies the checkout's bin/lib whole instead of naming ci_gate.py.
- merge_base_moved_test.sh: on_board's 10 paths over the boards '' and 'notes*/' (:186-193) are also driven through `swarm.sh merge` on a base that moved by those paths, so the live board_paths is checked. A path that cannot be driven from outside stays in py_on, and the PR names it; ci-gate-go-globs carries all 10 as a Go test.
- merge_ci_budget_test.sh: the wait records folder is checked from outside: a story merge's pending main wait has its record under .swarm/main-waits while it waits, and a --board merge's has none. The simulated clock (:18-60) and the spy's cap check stay; ci-gate-go-main and the switch take them.
- merge_rules_test.sh:1073-1080: the python3 stub that makes `ci_gate.py files-status` exit 7 becomes a gh stub that kills the process that started it on the files read, found without naming ci_gate.py. merge still says the read 'exited <n> and said nothing'.
merge_queue_test.sh's patched-copy case stays: its go_check (tests.tsv:100) is ci-gate-go-queued's.

**Done when:**
- (1) wait_pr_cache_test.sh, wait_pr_expected_test.sh and merge_rules_test.sh start no python3 of their own, write no python3 stub, and name no bin/lib file outside comments, but for the direct contracts the PR names. (2) board_only_test.sh names no bin/lib file, and every case prints the verdict it printed before. (3) On a worktree copy without .git where pages() never takes a kept read, wait_pr_cache_test.sh's 'one read of each kind per poll between them' goes red; where the cache keeps a read pages refused, the rejected-read check goes red; where WAIT_PR_FRESH no longer turns the cache off, the cache-off check goes red. (4) Each other rewritten check goes red on a worktree copy where what it guards is broken: checks() counting a pending check as green; on_board taking retros/x.sh as a board path; main_ci writing no wait record; pinned_files dropping the exit from its message. The PR quotes the FAIL lines. (5) make test TESTS='<the six files>' passes. (6) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

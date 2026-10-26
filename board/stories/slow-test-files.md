---
kind: code
status: ready
epic: test-speed
depends_on: []
touches: [tests/merge_test.sh:merge helper deadlines, tests/wait_pr_test.sh:wall-clock budgets, Makefile:SLOW comment]
estimate_lines: 120
easy: false
---

# merge_test and wait_pr_test get faster with the same assertions

Adopted: epic test-speed, status ready, touches as file:part. Replace the stale text ('20 to 55 minutes on 2026-10-24') with Appendix A's figures: 35 full local runs on 2026-10-24/25; median 1050 s and p90 1391 s for the 17 with no other run going; up to 3405 s with 7 going. Ranked in the plan from the per-file seconds in the test-shard logs of main's green CI runs 40238681988 and 40237857410 (2026-10-25; one runner per shard, `ok <file> <n>s`, scripts/test.sh:75). Top 10: merge_test 276/393, wait_pr_test 217/223, dash_check_test 131/147, queue_test 113/113, epic_wait_session_test 101/96, next_test 88/99, upgrade_test 96/84, flow_test 57/91, review_test 85/79, ci_health_test 60/81. Fix the two worst. merge_test: the merge() helper's deadlines (SWARM_MERGE_CI_SECONDS=5 and friends, tests/merge_test.sh:205-211) and the cases that wait them out. wait_pr_test: the wall-clock budgets ROOM, SLACK, LATE, HANG and PAUSE (tests/wait_pr_test.sh:29-33) and the cases that run to them. Use polls in place of fixed sleeps, and shorter budgets where a case does not need the room. No check is dropped or weakened. Makefile:20-23's SLOW comment gives per-file seconds; update it. Moving a file out of SLOW or SERIAL is ci-three-minutes'. The old touch `scripts/test.sh:shard balance` is dropped: four other stories edit scripts/test.sh. No other v0.28.0 story touches these two files; merge-holds (v0.29.0) will.

**Done when:**
- The PR lists the top 10 files by CI per-file seconds from main's run before and from its own head's run, and merge_test and wait_pr_test are each at least 30% faster on the same source.
- The PR lists, per changed file, every check's name and expected value before and after, matched one to one. Any changed value is explained, and for each sped-up wait case the builder breaks the behaviour the case guards (a deadline that is ignored) and shows the case goes red.

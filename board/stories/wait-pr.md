---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/swarm.sh:dispatch and usage header, bin/swarm.sh:READ_ONLY_COMMANDS, bin/lib/merge.sh:wait_pr (new), commands/swarm.md:PR waits, docs/reference.md:wait-pr row, README.md:commands list wait-pr, tests/wait_pr_test.sh (new), tests/events_test.sh:READ_ONLY list]
easy: false
estimate_lines: 150
---

# swarm.sh wait-pr <url> waits for a PR's checks and fails loudly

Builds on the split: ci_gate in bin/lib/merge.sh (bin/swarm.sh:3730; fail-closed and paginated: 1 red, 2 pending, 3 error). A new read-only command loops ci_gate on the PR's head until nothing is pending, printing the head SHA and each check with its state. It exits 0 when all are green and 1 on red. It exits non-zero at once on any gh error, which it never reads as pending. An empty check list is normal for a few minutes after a push (seen 2026-10-17), so it waits up to a grace period (a variable, 5 minutes by default) for checks to appear, then exits non-zero. It polls on the same variable as MERGE_POLL. No hand-written wait loop exists in commands/ or docs/, so commands/swarm.md and reference.md add wait-pr where the lead waits on a PR.

**Done when:**
- tests/wait_pr_test.sh: a failing gh stub makes wait-pr exit non-zero within one poll; an empty check list that stays empty past the grace (set near 0 in the test) exits non-zero, and one that fills in within it goes on waiting; pending then green exits 0 printing the head SHA and each check; red exits 1.
- tests/events_test.sh's READ_ONLY_COMMANDS list includes wait-pr.

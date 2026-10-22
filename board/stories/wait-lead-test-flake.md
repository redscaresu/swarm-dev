---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/wait_lead_test.sh]
easy: true
estimate_lines: 30
---

# wait_lead_test's "cached green head" case passes on every run, not only most

tests/wait_lead_test.sh's case near line 182, "a cached green head that a re-run turned red ..." / "a cached green head outlives a poll that could not read it", failed once on #360 and once on #374 on 2026-10-22, and passed on re-run both times. Find what the case depends on (a poll's timing, a cache file's mtime, or the order of two reads), the way #380 did for wait_pr_test: reproduce it with a slowed stub, then fix whichever side is wrong, the test or the code.

**Done when:**
- The PR shows the failure reproduced with a slowed or reordered stub, and the case passing under that same stub after the fix.

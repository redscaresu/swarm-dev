---
kind: code
status: ready
depends_on: []
touches: [Makefile:SLOW, .github/workflows/ci.yml:test-shard matrix, tests/test_shard_test.sh, AGENTS.md:Working on this repository shard count]
estimate_lines: 20
easy: true
---

# Give the three slowest test files a CI shard each

In CI run 43703607425 (main, 2026-11-15) the 12 test shards took 124 to 514 s, and the slowest shard set
the run's 9 minutes. Its slowest files were tell_queue (324 s), wait_lead (226 s) and dash_time_limit
(185 s), none of them in the Makefile's SLOW list, so each shares a shard with other files.

Add tests/tell_queue_test.sh, tests/wait_lead_test.sh and tests/dash_time_limit_test.sh to SLOW in the
Makefile. SLOW and SERIAL then hold 14 files, more than the 12 shards, and tests/test_shard_test.sh
requires ci.yml's shard count to be at least that, so raise the `test-shard` matrix to 14. Makefile and
.github/ are protected paths: `swarm.sh merge` holds this PR for the user.

**Done when:**
- Makefile's SLOW lists the three files, and its comment's list of SLOW files names them
- ci.yml's test-shard matrix has 14 shards, and tests/test_shard_test.sh passes
- AGENTS.md's two mentions of 12 `test-shard` jobs say 14
- The PR quotes the slowest shard's time from its own CI run beside the 514 s above
- scripts/select-tests.sh --run passes

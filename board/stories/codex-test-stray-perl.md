---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [tests/codex_test.sh, bin/swarm.sh:cmd_codex_review]
easy: true
estimate_lines: 40
---

# codex_test's TERM and KILL checks fail on a perl left from an earlier case

Main went red at 6822719 (run 39761860565, shard 4) and passed on a rerun. Both `codex-review sent TERM exits with neither a TERM-trapping stub nor its child left` and `a KILL to codex-review's process group leaves neither the stub nor its child` got `yes|no: 18632 perl`. That is the same PID in two cases, so the process outlived the case that started it. `gone()` (tests/codex_test.sh:64) pgreps `${BIN}/`, so the perl ran from the test's own stub dir. Find which earlier case leaves it: a real leak in codex-review's cleanup is a bug to fix in bin/, and a test-only leftover is cleaned up at the end of its own case.

**Done when:**
- The PR names which case started the perl and why it outlived it, with the evidence.
- tests/codex_test.sh passes 20 runs in a row under `SHARD`'s load (say how you loaded it), with each case checking that nothing under `${BIN}/` is left when it ends.

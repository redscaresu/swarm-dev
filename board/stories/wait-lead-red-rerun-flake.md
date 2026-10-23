---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: [wait-lead-test-flake]
touches: [bin/lib/lifecycle.sh:heads_green, tests/wait_lead_test.sh]
estimate_lines: 40
---

# wait --lead's "a cached green head that a re-run turned red" case: find its cause, and stop re-reading a red head every poll

wait-lead-test-flake (#388) fixed the timing of two wait_lead_test.sh cases but could not reproduce the one that failed in CI on #360 (run 39808495881): "a cached green head that a re-run turned red does not wake it". Its cause is still open.

Its review found one likely place: heads_green's first pass (bin/lib/lifecycle.sh, ~:1611) writes a cached "<url> <head>" to LEAD_GREEN.new before the LEAD_FRESH re-read (~:1651) finds that head red, and the awk at ~:1661 then keeps the red head in LEAD_GREEN. It never causes a wrong wake, but every later poll repeats the fresh re-read (one more `gh pr view` and ci_gate per poll), and the ordering is the kind of thing that could make that case flaky.

Fix heads_green so a head the fresh re-read finds red is not kept in LEAD_GREEN, and reproduce the #360 case with a slowed or reordered stub (as #388 did for its two cases).

**Done when:**
- tests/wait_lead_test.sh: the #360 case is shown failing under a slowed or reordered stub before the fix and passing after (or the PR says what it ruled out and why the case is now deterministic).
- A test with a stub gh shows a head the fresh re-read finds red is gone from LEAD_GREEN after that poll, and the next poll makes no fresh re-read for it.

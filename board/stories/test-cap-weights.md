---
kind: code
status: blocked
epic: machine-usable
depends_on: [cap-weight-decision, test-run-end-rows]
needs: [cap-weight-decision (the weight the user chose (proposed 1/10).), test-run-end-rows (its scripts/test.sh changes (trap order; marks) merged first; same file.)]
touches: [scripts/test.sh:cap (take_slot, free_slot, holder, wait loop), AGENTS.md:machine-wide cap paragraph, docs/running.md:Test tooling (cap line), tests/test_cap_test.sh:weight cases]
estimate_lines: 260
easy: false
---

# The test cap weighs a selected run below a full one

Uses the weight from cap-weight-decision, and builds on test-run-end-rows' scripts/test.sh and mutation-proof-on-copy's AGENTS.md. Today a slot is an integer dir 1..N holding one PID file, taken by atomic rename (scripts/test.sh:226-335), so every run weighs 1. Make a selected run (filter != all, test.sh:214-219) weigh the chosen fraction and a full run 1, admitted while the held weight stays within N; e.g. N x k unit slots, a full run taking k all-or-nothing (free what it took and retry on a short take, so two full runs never deadlock), a selected run 1. The weight is a constant, not a setting. Keep: the rename take, no/empty/0 cap file = no cap and nothing under ~/.swarm, a nested run takes none, gone-PID cleanup. Edit AGENTS.md's cap paragraph and docs/running.md:182 in this PR, and say in the PR that AGENTS.md changed. Read test-runs.tsv once at most; load at or under 4 CPUs.

**Done when:**
- tests/test_cap_test.sh, cap 1: k selected runs hold at once and the next waits; a full run waits while one selected run holds, and a selected run waits while a full run holds. Each goes red with the weight forced to 1.
- Two full runs and some selected runs started together under cap 1 all finish (no deadlock from partial takes).
- The existing invariants in test_cap_test.sh still pass: atomic slot rename, nothing under ~/.swarm with no, empty or 0 cap, a nested run takes none.
- The PR names the weight and the durations it came from; AGENTS.md's cap paragraph and docs/running.md say a selected run counts as that fraction.
- Cap 2: two full runs, or 2k selected runs, hold at once and the next waits.

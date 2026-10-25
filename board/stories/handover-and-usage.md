---
kind: code
status: later
depends_on: []
touches: [bin/swarm.sh:new handover command, bin/lib/reports.sh:usage estimate, tests/handover_test.sh (new), docs/reference.md:handover and usage entries]
estimate_lines: 200
easy: false
---

# swarm.sh handover and a usage warning, moved from the lead into swarm-dev

For 0.28 (0.27 retro, 2026-10-25). Lead-only practice from 2026-10-24 that every project should get.
- `swarm.sh handover <dir>`: write what another machine needs that is not in git. That is the project's `.swarm/` without session logs, a patch of the main checkout's uncommitted board edits, and a snapshot of open PRs and agents, plus a RESTORE.md. The lead's memory directory is copied only when the user names it, and it is never published.
- A usage estimate: price-weighted tokens since the weekly reset, from ~/.claude/projects/**/*.jsonl, calibrated against a `/usage` reading the user gives. Fable is weighted separately. On 2026-10-25 a single weighting read 90.6% while /usage showed 95%, because Fable's share was underweighted. `wait --lead` warns at a threshold the user sets.

**Done when:**
- tests/handover_test.sh: a fixture project's handover holds .swarm without sessions, the patch, the snapshot and RESTORE.md, and restoring it into a fresh clone gives the same board state.
- A test feeds fixture jsonl with Fable and Opus usage to the estimator and checks the two calibrated shares.
- `make test` passes.

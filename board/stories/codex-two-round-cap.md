---
kind: code
status: ready
fix: true
depends_on: []
touches: [bin/lib/build.sh:CAP_ROUND, docs/method.md:round cap, docs/reference-building.md:round cap, docs/reference-models.md:demote_kinds round cap, AGENTS.md:review-agent round cap, skills/swarm-dev/SKILL.md:round cap]
estimate_lines: 40
easy: true
---

# The review agent's round cap starts at round 2, not 3

The user, 2026-11-18: codex reviews slow every PR down, so cap them at 2 rounds. Today CAP_ROUND=3
(bin/lib/build.sh): from round 3 the review agent sends the builder only a regression the PR introduces or a
line now false about the code, and declines the rest as deferred. Set CAP_ROUND=2, so the cap holds from
round 2: round 1 sends every finding inside the story, round 2 on sends only regressions and false lines.

Update every doc and test that says the cap starts at round 3: docs/method.md, docs/reference-building.md,
docs/reference-models.md (demote_kinds adds nothing from round 2), AGENTS.md, skills/swarm-dev/SKILL.md, and
the tests that pin the round (tests/review_handoff_gaps_test.sh, tests/epic_codex_test.sh, tests/next_test.sh,
tests/conduct_backlog_test.sh, as each one needs). `flow`'s `round3_on` column (bin/lib/flow_review_loops.py)
stays: it measures history.

**Done when:**
- A review brief for round 2 carries the round-cap line, and one for round 1 does not; with CAP_ROUND back at
  3 the round-2 check fails (shown on a worktree copy, quoted in the PR)
- Every doc that named round 3 as the cap names round 2
- scripts/select-tests.sh --run passes

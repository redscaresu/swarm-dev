---
kind: code
status: blocked
epic: stage-gating
depends_on: [stage-release-gate]
needs: [stage-release-gate: its changes to tests/next_test.sh expect_release, which this story's recording must include]
touches: [tests/next_test.sh:expect recording, tests/next_test.sh:expect_release recording, tests/next_test.sh:expect_conductor recording, tests/next_test.sh:arm check (new, at the end)]
estimate_lines: 60
easy: true
---

# A test fails when next prints a step that commands/swarm.md has no arm for

Make tests/next_test.sh's helpers that run next (expect, expect_release, expect_conductor and any other) record the first word of each first line next prints. At the end, for each recorded step, check that commands/swarm.md has an arm line starting '   - `<step>' followed by a space or a backtick (the arms at commands/swarm.md:84-343), and fail naming each step with none. A self-check runs the same function on a copy of commands/swarm.md without the `release` arm and must fail naming release. Read next's output, never next_step's source. It edits expect_release, which stage-release-gate also edits: the touches clash keeps them apart. retro-gate's `retro` step story reuses this check.

**Done when:**
- tests/next_test.sh passes and the check names the steps it saw; it fails if any of fix-main, wait, collect, conduct, resume, story, plan-epic, plan-hld, hld, escalated, release, gate or done was not recorded.
- Its self-check fails naming `release` on a copy of commands/swarm.md without the release arm.
- Renaming one arm heading in commands/swarm.md, `gate` say, makes tests/next_test.sh fail naming that step.

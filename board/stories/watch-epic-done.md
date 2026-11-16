---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh:watch_command epic-done exit, tests/watch_opened_test.sh:epic-done cases, docs/reference-building.md:watch paragraph (§ Building) epic-done sentence]
estimate_lines: 80
easy: true
---

# watch --epic returns once the epic has no story left for an agent

On 2026-11-16 two conductors sat busy for hours after their epic's last PR merged, because their
`swarm.sh watch --epic <slug>` never returned: conduct-doc-hotspot's ran 15h28m after #968 merged
(2026-11-15 23:39), and conduct-retro-gate's 13h36m after #974 merged (2026-11-16 01:40). A busy
conductor cannot be collected, so `next` printed `wait conduct-<epic>` the whole time, ahead of every
later step (the v0.31.0 retro among them), until the lead killed each watch by PID.

`watch --epic <slug>` (bin/lib/merge.sh, watch_command) returns when a story PR needs the lead. Add an
exit: on a poll where the epic has no story an agent builds left on the board in ready, blocked or
review (only `kind: lead` stories, or none), and no story PR of the epic is open, print one line,
`epic-done: <slug> has no agent work left`, and exit 0, so the conductor writes its report. `--backlog`
and a bare `watch` behave as today.

**Done when:**
- tests/watch_opened_test.sh: a fixture epic whose last code story has merged (only a kind: lead story left,
  no open story PR) makes `watch --epic <slug>` print the epic-done line and exit 0 within one poll; with
  the change removed it keeps polling until the test's timeout (shown on a worktree copy, quoted in the
  PR)
- An epic with a code story still ready, blocked or in review keeps watching
- `watch --backlog` and a bare `watch` still never print the line
- docs/reference-building.md's watch paragraph names the epic-done line and the 2026-11-16 conductors
  as why
- scripts/select-tests.sh --run passes

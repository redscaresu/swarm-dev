---
kind: code
status: later
epic: less-noise
depends_on: []
touches: [bin/lib/board.sh:idle_lines, bin/lib/touches_rows.py:--idle, bin/lib/lifecycle.sh:lead_queue, commands/swarm.md:idle and wait --lead handlers, tests/concurrency_check_test.sh (new), docs/reference.md:idle lines]
estimate_lines: 250
easy: false
---

# After every merge, the lead hears what else can run now

Target: v0.29.0, adopted by less-noise, and shipped early in the v0.28.1 patch (user, 2026-10-26: "I want everything to run with max concurrency by default"). In the v0.28.0 build the lead often took a declared dependency for a real one and left slots idle, and the user caught it. next's idle_lines already flags a blocked story that shares no file with its dependency, but only when next runs, by whole file, and without reading `needs`.

Extend idle_lines, and show its lines in lead_queue (so wait --lead, status and dash carry them), recomputed after each merge event. Each line names its exit and alerts once per occurrence:
- `idle: <story> waits on <dep> but shares no touches part with it and needs nothing from it`: by file part (clash-by-part's rule), not whole file, and silent when `needs` names the dependency. Exit: the lead drops the dependency in a board PR, or writes why it is real in the story.
- `idle: <story> is ready with no build`: ready, buildable, no clash with a running build, and no build started for more than queue_minutes. Exit: the conductor's, else the lead starts it.
- `idle: epic <epic> can start`: a draft or planned epic in the current stage whose depends_on epics have all left the board, or whose stories are already ready. Exit: plan it, or set it active in a board PR.
- `idle: epic <epic> has no plan running`: an active epic with no stories and no /plan-epic agent. Exit: /swarm-dev:plan-epic <epic>.

Reads stay inside wait --lead's poll budget: the board and state only, no gh call.

**Done when:**
- A test per line kind fires on its real case and stays silent on its false case (a dependency sharing a touches part; one named in `needs`; a ready story clashing with a running build; an epic whose dependency is still on the board).
- commands/swarm.md has an arm for each kind, and the handler-coverage test covers them.
- next's existing `idle: <story> waits on <dep>` test still passes, now by part.
- `make test` passes.

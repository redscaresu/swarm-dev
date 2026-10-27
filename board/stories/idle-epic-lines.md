---
kind: code
status: blocked
epic: stuck-work
depends_on: [idle-ready-no-build]
needs: [idle-ready-no-build: touches_rows.py --idle and the next idle list as it leaves them (shared parts)]
touches: [bin/lib/touches_rows.py:--idle, commands/swarm.md:next idle list, tests/idle_epic_test.sh (new), docs/reference.md:idle lines]
estimate_lines: 150
easy: false
---

# idle: an epic that can start, and an active epic with no plan running

Uses idle-ready-no-build's --idle mode and next idle list (shared parts). touches_rows.py --idle adds `idle: epic <epic> can start, exit: plan it, or set it active in a board PR` for a draft or later epic in the current stage whose depends_on epics have all left the board or whose stories are already ready, and `idle: epic <epic> has no plan running, exit: /swarm-dev:plan-epic <epic>` for an active epic with no stories and no scope-<epic> plan recorded in .swarm/state. Board and state only. An epic next's `stage v<T>` line already covers gets no idle: line. commands/swarm.md's next idle list gets an item for each.

**Done when:**
- tests/idle_epic_test.sh (new): each line fires on its real case and stays silent when a dependency epic is still on the board, when the stage line covers the epic, and when a plan for it is recorded. Each check fails with its condition removed.
- commands/swarm.md's next idle list has both lines, checked against what touches_rows.py prints.

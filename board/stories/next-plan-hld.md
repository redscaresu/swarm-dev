---
kind: code
status: ready
epic: plan-hld
depends_on: []
touches: [bin/lib/board.sh:next_step and its usage comment, new hld_epics and hld_planned, tests/next_test.sh, tests/removed_test.sh, tests/dash_needs_you_test.sh]
estimate_lines: 120
easy: false
---

# next prints plan-hld for an unplanned agreed HLD, and hld once a planned HLD's epics have all left

Needs nothing from another story. Run the epic's **Checks before every stage**.

In bin/lib/board.sh:
- `hld_epics <hld name>` lists the board's epics whose front-matter `hld:` (get_fm and slug_list, never fm, which can match a body line: board.sh:5) equals the name exactly, with no `.md`. It reads `hld:` the way grants-reader's item_hld does.
- `hld_planned <hld file>` is true when the HLD's front matter has a `planned:` line (get_fm). /plan-hld's board PR sets it (plan-hld-command). Links under `## Epics` are informational and decide nothing: a link a person adds by hand must not make an unplanned HLD look finished.

next_step gets two arms. Neither calls gh, since dash runs next every frame (board.sh:432-437), and neither fires for a draft or superseded HLD or for the README.
- `plan-hld <hld>`, after plannable_epic and before escalated, where #293 removed it (git show 45b2af1a bin/lib/board.sh): an agreed HLD with no `planned:`. It skips an HLD whose plan board-PR worktree (`<repo>-wt/_board-plan-<hld>`, a local directory test, no gh) exists and falls through to the next arm, so an open plan PR does not hold up escalated, release or gate.
- `hld <hld>`, just before gate: an agreed HLD with `planned:` and no hld_epics. Its why says to run `swarm.sh finish <hld>`. While `<repo>-wt/_board-finish-<hld>` exists, the HLD is a gate row instead, `finish PR awaiting merge: <hld>`, so a finish PR waiting on the user stays visible and `next` never says done while the HLD is still there.

Add both arms to the usage comment (board.sh:150-185). tests/removed_test.sh drops its plan-hld and hld-lead grep and the commands/plan-hld.md-absent check (:36-42), with their header sentence (:5-6): this is the first story that writes plan-hld into bin/. There is no new status, so Board.base is unchanged; tests/dash_needs_you_test.sh pins dash.

The lead cuts no release between this story's merge and plan-hld-command's (the epic's Checks).

**Done when:**
- tests/next_test.sh: an agreed HLD with no `planned:` prints `plan-hld <hld>`, even when its `## Epics` holds a hand-written link; with `_board-plan-<hld>` present it falls through to the next arm (a gate fixture shows the gate); an agreed HLD with `planned:` and one epic carrying its `hld:` gives plan-epic, not plan-hld or hld; an epic whose `hld:` only shares a prefix with the name does not count; with `planned:` and no epics it prints `hld <hld>`, and with `_board-finish-<hld>` present it prints the gate with a `finish PR awaiting merge: <hld>` row instead; a draft HLD gives the gate's `draft hld:` line; a superseded HLD with `planned:` prints neither; the README is never named. The existing 'agreed and superseded HLDs are ignored' case (next_test.sh:~66) is rewritten to match.
- tests/dash_needs_you_test.sh: an agreed unplanned HLD has no needs-you row and the header's next names `plan-hld <hld>`; a draft HLD keeps its `agree draft HLD` row.
- tests/removed_test.sh no longer greps for plan-hld or hld-lead, and passes.
- `make test` passes.

---
kind: code
status: ready
epic: plan-hld
depends_on: []
needs: grants-reader (merged) grants() and hld_grants in bin/lib/board.sh
touches: [bin/lib/board.sh:grants, tests/grants_test.sh]
estimate_lines: 40
easy: true
---

# swarm.sh grants <hld> prints an agreed HLD's own grants

Uses grants-reader's grants() and hld_grants (bin/lib/board.sh:575, :677), merged. Run the epic's **Checks before every stage**.

/plan-hld reads an HLD's grants before its epics exist on the board, and grants() resolves its argument with item_file, which knows only stories and epics. Keep item_file's slug check (`^[a-z0-9-]+$`, board.sh:~893) and its lookup first: a story or epic with the slug wins. Only when neither has it, fall back to `<board>/hld/<arg>.md`, between item_file's slug check and its die: an agreed HLD prints itself and hld_grants; a draft or superseded one prints `none`. HLD names are dated (YYYY-MM-DD-<slug>) and pass the slug check. Reuse hld_grants; write no second reader. Do not write plan-hld in bin/ until next-plan-hld merges (tests/removed_test.sh). The usage line is plan-hld-command's.

**Done when:**
- tests/grants_test.sh: `swarm.sh grants <hld>` for an agreed HLD with `grants: [epics, merge]` prints the HLD file, then epics and merge; with no grants: the file, then none; a draft and a superseded HLD each print `none`; a bad grant value dies with the HLD's file and line; a story and an agreed HLD with the same name resolve to the story; `grants ../epics/x` dies with bad slug.
- `make test` passes.

---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh, bin/lib/build.sh, tests/hold_test.sh]
estimate_lines: 80
easy: true
---

# A conductor logs every ready story it holds back, and why

On 2026-10-24 conduct-epic-guard held its two ready stories (epic-agreed-line, lead-epics-key) for about 50 minutes because they shared docs/reference.md and tests/plan_epic_test.sh with another epic's open PR (#432). It decided that in its own turn, so nothing recorded it: the lead found it by reading the pane. The user wants data on what is held and why.

- Add `swarm.sh hold <slug> <why>`: it appends an events.tsv line (`hold`, the slug, the reason) through the existing event logger in bin/lib/agents.sh, and dies on a slug that is not a ready story on the board.
- `startable_rule` in bin/lib/build.sh tells the conductor: for each `startable:` story it does not start, run `swarm.sh hold <slug> '<why>'` once per wave, naming what it clashes with (story or PR) and the shared files, or the other reason (give-up rule, closed this wave, `not held:`). Log it again only when the reason changes.
- Document `hold` in swarm.sh's usage header and docs/reference.md's command list.

**Done when:**
- tests/hold_test.sh: `hold <ready story> 'touches docs/x.md with #432'` writes one events.tsv line with the command `hold`, the slug and the reason; `hold` on a missing or non-ready story dies and writes nothing.
- The conductor brief that build.sh renders contains the `swarm.sh hold` instruction (a test greps it).
- `make test` passes.

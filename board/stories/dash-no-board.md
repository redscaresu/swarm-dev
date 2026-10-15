---
kind: code
status: ready
epic: dash-tells-the-truth
depends_on: []
touches: [bin/swarm.sh:dash, tests/dash_test.sh (new block after :150), docs/dash.md (one line), board/stories/dash-no-board.md (epic: line)]
---

# dash in a folder with no board says so and names swarm.sh init

Absorbed into this epic by slug: keep board/stories/dash-no-board.md, add `epic: dash-tells-the-truth`. At the top of dash() (bin/swarm.sh:2629), before dash_size so --watch is covered too: when `${BOARD}/stories/README.md` is missing (init's marker, bin/swarm.sh:3790-3800), die with one line naming 'no board' and `swarm.sh init`. dash is read-only and in READ_ONLY_COMMANDS (:3889), so nothing is logged. Put the checks in tests/dash_test.sh right after the first-frame/snapshot checks (:144-150), apart from the hunks other wave-1 stories add. One line in docs/dash.md.

**Done when:**
- tests/dash_test.sh: `dash` and `dash --watch 1` in a temp git repo with no board each exit non-zero within 5 s, print a line containing 'no board' and 'swarm.sh init', and do not contain 'nothing needs you'. `dash` on a board with no stories in progress or waiting prints 'nothing needs you' and exits 0. The PR shows the new checks failing with the guard removed. The epic's checks before every stage pass.

**From review (binding; overrides the scope above where they differ):**
- Put its test in its own file (tests/dash_noboard_test.sh) or at the end of tests/dash_test.sh, never next to the header regex at :151 that dash-escalation rewrites. `next` does not die in a git repo with no board, so do not cite it as the model; dash dies with its own message.

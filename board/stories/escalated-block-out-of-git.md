---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/lifecycle.sh:lead_block, held_story, bin/lib/board.sh:reset_story, impossible_block, docs/reference.md:§ escalation block paragraph, tests/escalated_block_test.sh (new)]
easy: false
estimate_lines: 120
---

# The escalated block that lead_block writes lives in .swarm/state, not in the story file

Builds on the split: lead_block and held_story in bin/lib/lifecycle.sh, reset_story and impossible_block in bin/lib/board.sh. lead_block appends an ESCALATED_OPEN..CLOSE block to the tracked story (bin/swarm.sh:6268-6274), reset_story rewrites the file to remove it (:3497-3505), and impossible_block reads it (:3314). Write the block to .swarm/state/board/stories/<slug>.escalated instead, read it from there in impossible_block, and delete it in reset_story; the kind, escalated_from and held_for lines still go through set_fm. docs/reference.md tells the lead where to read the block. Independent of board-state-out-of-git: with or without it, the block never touches the tracked file.

**Done when:**
- tests/escalated_block_test.sh: on a fixture repo whose story front matter is already committed, lead_block (through `close` of a failed build or `held_story`) leaves the story file's body unchanged and writes the .escalated file; `next` still names the story as escalated, and impossible_block reads the block from state.
- The same test: `swarm.sh reset <slug> <reason>` deletes the .escalated file and leaves the story file's body unchanged.

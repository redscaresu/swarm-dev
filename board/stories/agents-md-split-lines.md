---
kind: lead
status: blocked
epic: swarm-sh-split
depends_on: [split-bash, board-prep]
touches: [AGENTS.md:pre-PR list and layout block, board/epics/safer-faster-swarm.md:status, board/epics/swarm-sh-split.md]
easy: false
estimate_lines: 15
---

# Right after the split, the lead updates AGENTS.md's shellcheck, py_compile and layout lines and releases the main epic

AGENTS.md is the lead's (AGENTS.md:70). One PR: the pre-PR list runs `shellcheck bin/swarm.sh bin/lib/*.sh scripts/pre-commit tests/*.sh` and `python3 -m py_compile bin/lib/*.py` (AGENTS.md:78-80), and the layout block names bin/lib/ next to bin/swarm.sh, which is no longer 'the only script' (AGENTS.md:80-90). Then, with board-prep done, a board PR sets safer-faster-swarm from status: later to active (never `conduct`'s uncommitted edit, bin/swarm.sh:3052-3054) and removes the swarm-sh-split epic file.

**Done when:**
- AGENTS.md on this PR names bin/lib/*.sh in the shellcheck command, has the py_compile line, and its layout block lists bin/lib/.
- The board PR sets board/epics/safer-faster-swarm.md to status: active and deletes board/epics/swarm-sh-split.md.

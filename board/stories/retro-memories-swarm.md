---
kind: code
status: ready
epic: retro-report
depends_on: []
touches: [bin/lib/retro_memories.py:note filter, tests/retro_test.sh:memories filter cases, docs/reference-logs.md:memories paragraph (swarm.sh retro)]
estimate_lines: 70
easy: true
---

# swarm.sh retro lists only the lead's swarm-dev memory notes

`swarm.sh retro`'s memories section (bin/lib/retro_memories.py) lists every `*.md` in the lead's memory folder but MEMORY.md, so each one can be placed in the framework, a rule or a check, or dropped. On 2026-11-14 the lead's project memory folder became a link to the user's personal memory store, which also holds notes that have nothing to do with swarm-dev (a kanban pointer, for one). The retro would then list those as items to place.

List a note only when it is a swarm-dev note: its front matter has `project: swarm-dev` (under `metadata:` or at the top level), or its `name:` or `description:` contains `swarm` (any case). After the list, print one line with how many other notes were skipped, so a note that should have been tagged is still noticed: `<n> other notes skipped (not tagged project: swarm-dev)`. Read only each note's front matter for the filter, and the name and description as today.

**Done when:**
- tests/retro_test.sh: a memory fixture with a note tagged `project: swarm-dev`, a note named `swarm-lead-decides` with no tag, and a note about something else lists the first two and prints `1 other notes skipped`
- A note with `swarm` only in its body, not its name, description or front matter, is skipped
- The existing empty-folder and missing-folder cases still print as today
- The tagged-note case goes red with the filter removed (all three listed), shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- docs/reference-logs.md's memories paragraph under swarm.sh retro names the filter and the skipped line
- scripts/select-tests.sh --run passes

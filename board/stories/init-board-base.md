---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/lifecycle.sh:init_project, docs/reference.md:init, tests/init_test.sh:Board.base cases]
estimate_lines: 90
easy: true
---

# init updates an unchanged older Board.base

init_project (bin/lib/lifecycle.sh:1932-1942) leaves every template file that exists, so a board's Board.base never gains views added later, such as the hld view. Replace an existing Board.base only when its bytes match a Board.base the plugin shipped before. Keep those versions' hashes (from `git log -- templates/docs/Board.base`) in lifecycle.sh, not under templates/docs/, which init copies. Leave an edited Board.base as it is, and print a line saying the template changed and how to compare. A second run changes nothing, and nothing a board set is removed. Update docs/reference.md's init text, and README.md if it describes init's output.

**Done when:**
- tests/init_test.sh: a board holding a past template's Board.base gets the current one and an 'updated' line. Fails on the base.
- A board with an edited Board.base keeps its bytes and gets the note, and a second init run updates nothing.

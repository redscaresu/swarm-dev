---
kind: code
status: ready
epic: fixes-027
depends_on: []
touches: [bin/lib/dash_finished.py:BOARD_OWN, tests/dash_finished_test.sh:hld and obsidian fixtures, bin/lib/board.sh:grants usage, bin/lib/merge.sh:ci_gate files-status comment, tests/grants_test.sh:usage case]
estimate_lines: 60
easy: true
---

# dash_finished treats hld/ and .obsidian/ as the board's own; grants' usage and the files-status comment

(1) BOARD_OWN (bin/lib/dash_finished.py:31) lists stories/, epics/, Board.base and README.md. So a commit that changes only hld/ or .obsidian/ counts as work (:39-40), and a story it removes reads as finished. Add hld/ and .obsidian/, the board's own paths in bin/lib/merge.sh:791 and docs/reference.md:1963. No test covers dash_finished.py today. (2) grants()' usage line (bin/lib/board.sh:1194) names an HLD: `<story | epic | hld | PR URL>`. (3) The ci_gate files-status comment (bin/lib/merge.sh:73-75) lists every file status GitHub returns, not four.

**Done when:**
- A fixture-repo test: a commit that deletes a story file and changes only board/hld/ is not counted as the story finishing with work, and neither is one that changes only board/.obsidian/. A commit that also changes code is. The hld and .obsidian cases fail on the base.
- `swarm.sh grants` with no argument prints a usage line that names hld. A test pins it and fails on the base.

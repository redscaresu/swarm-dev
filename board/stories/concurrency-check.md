---
kind: code
status: ready
epic: stuck-work
depends_on: []
touches: [bin/lib/touches_rows.py:--idle, commands/swarm.md:next idle list, tests/concurrency_check_test.sh (new), tests/next_test.sh:idle waits-on check, docs/reference.md:idle lines]
estimate_lines: 100
easy: false
---

# next's idle dependency line goes by touches part and reads needs

Re-scoped by less-noise: this story is the by-part dependency check; idle-lines-in-lead-queue, idle-ready-no-build and idle-epic-lines take the rest of its old text. touches_rows.py --idle (bin/lib/touches_rows.py:89-102) prints `idle: <story> waits on <dep> but shares no touches with it` by whole file. Compare by part with clash-by-part's rule (same file and same first word of the part, past a leading §, #, the, a or an; or both bare), as story --strict does, and stay silent when the story's needs names the dependency. The line becomes `... shares no touches part with it and needs nothing from it`, naming its exit. commands/swarm.md's next idle list (:63-74) quotes the line (:65): update it to the new wording and the needs rule.

**Done when:**
- tests/concurrency_check_test.sh (new): a dependency sharing a part gives no line; one sharing the file with other parts gives the line; one named in needs gives none. Each fails with the old by-file compare.
- tests/next_test.sh's `idle: <story> waits on <dep>` check passes with the new wording.
- commands/swarm.md's next idle list quotes the new line; the concurrency test checks the quoted text matches what touches_rows.py prints.

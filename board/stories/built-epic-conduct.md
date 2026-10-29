---
kind: code
status: ready
epic: lead-woken
depends_on: []
touches: [bin/lib/board.sh:epic_built (new), bin/lib/board.sh:epic_report_stale (new), bin/lib/board.sh:plannable_epics, bin/lib/board.sh:next_step built-epic arm, tests/next_test.sh:built epic cases, tests/idle_epic_test.sh:built epic case, commands/swarm.md:the conduct arm for a built epic, docs/reference.md:next's built-epic step, docs/method.md:next's step order]
estimate_lines: 220
easy: false
---

# next sends a built, unreported epic to conduct instead of plan-epic

next showed four fully built epics as needing a plan (#703 to #706). Add epic_built <epic> in board.sh, beside epic_planned (112-122). It is true for an active epic with no story files whose stories were planned and have all left the board, read from the board's history: dash_finished, or epic_deleted_here for a deletion not yet committed. Unlike epic_planned, it is false on a board with no git history, so a never-planned epic there still gets plan-epic, as today. plannable_epics (822-830) leaves a built epic out. That also takes it out of idle_epic_lines' active arm (466-500) and the running-conductor block's plan-epic (board.sh:258-262). next_step gets an arm before its plan-epic arm (board.sh:298-299) that prints `conduct <epic>`, with a why naming the epic as built with no report, or with a report older than its last story's merge. It fires for a built epic with no .swarm/conduct-<epic>.report.md, or one older than the newest merge of its stories. Read that merge in a new epic_report_stale the way release_stage reads deleted stories (board.sh:958-978: git log --first-parent --diff-filter=D, and the epic: of the deleting commit's parent), here with the commit time. Run that git log only for a built epic that has a report file, so most dash frames pay nothing. A built epic with a fresh report gets neither step. The conductor that starts writes its report and Finish PR at once, as a conductor with no agent work left does today: no change there. Docs: commands/swarm.md's conduct arm (a built epic's conductor reports at once; collect it as usual) and next's steps in docs/reference.md.

**Done when:**
- tests/next_test.sh built epic cases: an active epic whose only story was deleted in a commit on the board's history, with no report, gets `conduct <epic>` from next.
- The same epic with a report older than that commit gets `conduct <epic>`; with a report newer than it, next prints neither `conduct <epic>` nor `plan-epic <epic>`.
- A never-planned active epic in a repo with history still gets `plan-epic <epic>`. On a board with no git history, an active epic with no stories gets plan-epic as today, and tests/next_test.sh:192 passes.
- tests/idle_epic_test.sh: a built epic gets no `idle: epic <epic> has no plan running` line; a never-planned one still does.
- Removing the epic_built check from plannable_epics turns the stale-report case red: it prints plan-epic (copy-aside proof).

---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/merge.sh:ready_tell, bin/lib/merge.sh:conduct_ready, docs/reference-merging.md:board PR ready note (the merge --board paragraph in § Merging), docs/lead-by-hand.md:A new epic with no conductor, tests/merge_board_root_test.sh:ready_tell cases, tests/next_test.sh:empty active epic case]
estimate_lines: 220
easy: false
---

# merge --board says why it started no conductor, and an empty active epic waits for plan-epic (#697)

#697 (HLD:459-460). Evidence from the live .swarm/events.tsv (gitignored; quoted here by the scoping run, which covers the epic's Your part step 2): `2026-10-27T00:11:27Z merge https://github.com/redscaresu/swarm-dev/pull/575 w20:p1 ok` (board: plan merge-holds; main-ci ok 00:16:32Z) and `2026-10-27T00:28:38Z merge https://github.com/redscaresu/swarm-dev/pull/576 w20:p1 ok` (board: plan fixes-027; main-ci ok 00:32:58Z). The lead started both conductors by hand (`conduct merge-holds` 00:23:48Z, `conduct fixes-027` 00:44:06Z), and its incident at 00:23:59Z reads: merge --board of a plan PR (#575) printed 'no conductor runs for it yet' but started none. That line was ready_tell's; conduct_ready then (main at 9008f5f7, merge.sh:444-493) had two silent exits, an empty `board_ready --started` return and a `continue` for a conductor name that has a pane, and they are still silent (merge.sh:1300-1301, 1317-1320); ready_tell also returns silently with no upstream (1561). Change: ready_tell prints one line whenever it starts no conductor for a group it found, and one when nothing is new, naming why (no upstream; no story this PR made ready; a conductor already runs and was noted; each conduct_ready skip). conduct_ready also runs from next_report on a wait (board.sh:732-737), so next's output must not change: the lines come through ready_tell (an argument to conduct_ready, say), not conduct_ready's default path. An epic the PR set active with no stories: no conductor (stop_rule, build.sh:61-72, would report at once and finish it unplanned), no report file, and the line `epic <e> is active with no stories: plan it (next offers plan-epic <e>)`; next already offers it (plannable_epic, board.sh:408 and 942-955): pin that. Tests for ready_tell live in tests/merge_board_root_test.sh:252-273 (merge_test.sh and conduct_backlog_test.sh, which the epic names, do not cover it). Remove docs/lead-by-hand.md's 'A new epic with no conductor' block (52-57). The first two cases below pin today's behaviour: they pass before the change and are kept as guards, not as the proof. The proof is the silent paths: reproduce each one (board_ready --started returning empty, a conductor name that already has a pane, ready_tell with no upstream) in a test that prints nothing today and a line after.

**Done when:**
- tests/merge_board_root_test.sh: merge --board of a PR that files ready stories under an active epic with no conductor running prints `started: conduct-<e>`. (a pin: it passes today too)
- tests/merge_board_root_test.sh: a PR that sets active an epic that has ready stories starts that epic's conductor. (a pin: it passes today too)
- Three cases for today's silent paths (board_ready --started empty, a conductor name that has a pane, no upstream) each print one line naming why no conductor started; each goes red with its line removed.
- tests/merge_board_root_test.sh: a PR that makes no story ready prints a line saying so, and events.tsv gets no conduct line.
- tests/merge_board_root_test.sh: a PR that sets active an epic with no stories prints the plan-it line, starts no conductor and leaves no .swarm/conduct-<e>.report.md; `swarm.sh next` on that board prints `plan-epic <e>`.
- tests/merge_board_root_test.sh: with a conductor of the epic in the herdr stub's list, merge --board names it and starts none.
- tests/next_test.sh: the existing conduct_ready cases on a wait (1583-1652) pass unchanged.
- docs/reference-merging.md lists the new lines, docs/lead-by-hand.md has no 'A new epic with no conductor' block, and the PR body shows each silent-path case red with its fix removed.

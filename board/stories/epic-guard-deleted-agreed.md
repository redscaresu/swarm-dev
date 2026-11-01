---
kind: code
status: ready
epic: deferred-700
depends_on: []
touches: [bin/lib/board.sh:epic_unticketed, tests/merge_rules_test.sh:epic guard cases, tests/board_pr_test.sh:epic guard cases, docs/reference-merging.md:epic guard paragraph (§ Merging, :169-176), docs/reference-lead.md:board-pr open guard paragraph (§ The lead, 42-47)]
estimate_lines: 140
easy: false
risk: high
---

# The epic guard refuses an agreed: date carried over from a deleted epic

#700 item 13 (#654). The epic guard is a safety path: it stops an epic going active without the user's ticket. epic_unticketed (bin/lib/board.sh:1338-1400) reads an epic absent at the base as new unless git pairs it as a rename. A PR that deletes a draft epic and adds an active one under another path, rewritten past git's half-alike bar, passes epic_ticket_agreed (:1411-1419) with the deleted epic's agreed: date, so it needs no other ticket. #654's fix: an agreed: date that any epic the PR deletes had at the base is no ticket. The deleted paths are already in [changed] (every path the PR changes, old paths too); a deleted epic reads absent at the head and present at the base through the same reader, so no reader change should be needed (check board-pr open's reader, lifecycle.sh:31, and merge.sh's). Update docs/reference-merging.md § Merging's epic guard paragraph (:169-176) where it says a rewrite reads as new. Tests in tests/merge_rules_test.sh and tests/board_pr_test.sh epic-guard cases (merge_rules_test.sh:717-730 ren helper). Prove each case fails with the check removed, on a worktree copy. Correction: the 'more than half rewritten reads as new' sentence is in docs/reference-lead.md:42-47 (board-pr open's guard paragraph), not reference-merging.md:169-176; reference-merging.md:175 also needs the deleted-epic case. The new read of the deleted epic at the base fails closed like every other guard read: a read error refuses (board.sh:1366, 1381). The refusal names the deleted epic whose agreed: date was reused, and reference-lead.md gives the way out for two epics agreed the same day: delete in one PR and add in another, or use parent:/hld:. Test refs: the ren helper is at tests/merge_rules_test.sh:777-778; the deleted-plus-unrelated case to sit beside is rnu at tests/board_pr_test.sh:501-504.

**Done when:**
- tests/merge_rules_test.sh: a PR that deletes a draft epic with agreed: D and adds an unrelated-path active epic with agreed: D, under the rename bar, is held by the epic guard; with a fresh agreed: date it passes
- tests/board_pr_test.sh: board-pr open refuses the same delete-and-re-add
- Both refusals go red with the deleted-epic check removed, shown on a worktree copy
- docs/reference-merging.md's epic guard paragraph names the deleted-epic case; scripts/select-tests.sh --run passes
- tests/merge_rules_test.sh: a 502 on the deleted epic's base read refuses with 'gh cannot read docs/epics/<old>.md at main', and goes red with the fail-closed read removed (worktree copy).
- The refusal names the deleted epic whose agreed: was reused, and docs/reference-lead.md gives the way out.

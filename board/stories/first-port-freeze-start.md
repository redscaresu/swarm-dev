---
kind: lead
status: ready
epic: first-port
depends_on: []
touches: [board/epics/helpers-panes.md:title, Done when and Areas]
estimate_lines: 0
---

# Lead: start the freeze: the 8 v0.30/0.31 epics are off the board, the 6 ready lead stories cleared or dropped, and #547 and #557 decided

The epic's Your part, before its first story starts (HLD:343-345). Every wave-1 story depends on this one, so nothing builds before the freeze. The epic's own depends_on cannot hold this: an epic's depends_on holds only its planning, never its stories' starts (bin/lib/board.sh:1417 epic_holding_deps, :1430 dep_holds).
- Done: release-client left the board in #1156 (0d9729f7). Its real-release check's gap, an older release's signed binary installed under a newer name, is closed by binary-attest-release-commit (ready, fix: true, risk: high, no epic: line). A fix: true story passes the freeze, and board/epics/foundation-exit.md says v0.32.0 should ship with it. Nothing here waits on it.
- Lead: finish or close the 8 active epics of the v0.30/0.31 HLD: board-loose-ends, doc-hotspot, flaky-tests, merge-mechanics, reliable-runs, review-yield, stalls-and-effort, status-speed.
- **You:** clear or drop each ready lead story: status-speed-readings (it times `status` in bash, so it must run before status is ported: open question 2), reliable-runs-readings, flaky-tests-readings, doc-hotspot-reading, ppid-check-after-review, review-follows-live-check.
- **You:** decide the three that keep epics open: effort-trial (blocked), release-confirm-answer (blocked), review-yield-tuning (later).
- **You:** merge or close PR #547 (board: check stories for five recurring finding kinds) and PR #557 (the dependabot codeql-action bump). Both were OPEN on 2026-11-23 (gh pr view).
- Lead: the dropped-lines fix is on main: d688799c (#1021) is an ancestor of f57291a6. Nothing is left to do for it.
- Lead: in the board PR that adds these stories, take require_trusted out of helpers-panes: its title, its Done when ('None of the 10 files') and its Areas ('9 of the 10') (board/epics/helpers-panes.md:7,11).
- Lead: from the first story's start, hold the freeze in every plan: main takes only port stories, their test rewrites, fix: true stories and fix-main builds (HLD:343-348).

**Done when:**
- (1) board/epics/ has no file for any of the 8 epics named. (2) None of the 6 ready lead stories, effort-trial, release-confirm-answer or review-yield-tuning is on the board as ready, and the board PR says what the user chose for each. (3) gh pr view 547 and gh pr view 557 each show MERGED or CLOSED. (4) board/epics/helpers-panes.md names 9 helpers and no longer names require_trusted. (5) This story's file is deleted, which lets wave 1 start.

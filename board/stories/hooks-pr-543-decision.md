---
kind: lead
status: ready
epic: telemetry-writers
depends_on: []
touches: []
estimate_lines: 0
easy: false
---

# Lead: merge or close board PR #543 before telemetry-hooks starts

The epic's Your part, step 2: #543 was to be decided before this plan and is still open (2026-10-30). **You:** merge or close board PR #543 (Board: hooks keep the live events.tsv clean). It adds story hooks-keep-live-events-clean, whose touches (hooks/merge-guard.sh:record, hooks/lead-stop.sh:log) are telemetry-hooks' parts. If it merges, the lead adds that story to telemetry-hooks' depends_on.

**Done when:**
- gh pr view 543 -R redscaresu/swarm-dev reads MERGED or CLOSED.
- If MERGED, telemetry-hooks' depends_on names hooks-keep-live-events-clean while that story is on the board.

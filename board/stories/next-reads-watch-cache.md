---
kind: code
status: blocked
epic: status-speed
depends_on: [watch-poll-cache]
needs: [watch-poll-cache (reliable-runs) (the SWARM_POLL_CACHE switch on queued_line's ci_gate call; poll_cache.py's entries and max age; and its docs/reference-building.md watch paragraph)]
touches: [tests/next_watch_cache_test.sh (new), docs/reference-building.md:watch paragraph (§ Building), bin/lib/board.sh:next_queued (only if the test shows the switch does not reach it)]
estimate_lines: 90
easy: true
---

# next's queued lines reuse the CI reads watch cached

Needs from watch-poll-cache: the SWARM_POLL_CACHE switch it sets on queued_line's `ci_gate age` call (merge.sh:2720), poll_cache.py's entries, and its edit of docs/reference-building.md's watch paragraph. next's only CI reads are conductors_queued -> queued_prs -> queued_line's ci_gate age, per open mergeable PR (board.sh:498, next_queued :692). An env prefix on a function call reaches the function's children in bash 3.2 (checked), so the switch should reach next_queued's ci_gate wrapper (report_read -> python3). Pin that with a test. Change board.sh:next_queued only if the test shows next misses the cache. queued_prs' `gh pr list ... mergeable` read stays uncached: a cached MERGEABLE would hide a conflict, as watch-poll-cache keeps pulls/<n> uncached. The read stays under report_read's deadline and keeps its skipped name `ci_gate age`.

**Done when:**
- tests/next_watch_cache_test.sh: with a stub herdr showing one working conductor and a stub gh that logs calls, a watch poll followed by next within the cache's max age logs no check-runs or status read by next for the head watch read; with the cache off, next logs its own.
- Same file: a head that moved after watch's poll is read fresh by next, and next's queued: line for a green head matches the cache-off run's.
- Same file: with the switch removed from queued_line's ci_gate call, the test goes red.
- next_time_limit_test.sh passes unchanged (a cut read is still named `ci_gate age`).
- docs/reference-building.md's watch paragraph says next's queued: lines read the same cached CI reads.

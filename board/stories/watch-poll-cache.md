---
kind: code
status: blocked
epic: reliable-runs
depends_on: [wait-pr-poll-cache]
needs: [wait-pr-poll-cache (bin/lib/poll_cache.py (its entry format; success-only writes; max-age read) and the SWARM_POLL_CACHE switch on ci_gate.py pages())]
touches: [bin/lib/poll_cache.py:command form, bin/lib/merge.sh:watch_rows, bin/lib/merge.sh:watch_mergeable, bin/lib/merge.sh:watch_prs (check-runs read), bin/lib/merge.sh:queued_line, tests/watch_cache_test.sh, docs/reference-building.md:watch paragraph (§ Building)]
estimate_lines: 180
easy: false
---

# Concurrent watches share their GitHub reads

Needs from wait-pr-poll-cache: bin/lib/poll_cache.py (success-only entries, reader-side max age) and the SWARM_POLL_CACHE / SWARM_POLL_CACHE_SECONDS switch on ci_gate.py's pages(). Each running watch (every conductor's watch --epic, plus the lead's) polls every 60 s (merge.sh:2883). Each poll reads the open-PR list (watch_rows, 2908), pulls/<n> (watch_mergeable, 2920), check-runs per head (2829) and queued_line's `ci_gate age` (2715-2735). Watch made 10,219 of the 40,197 REST calls in the same gh-calls.tsv window. Give poll_cache.py a command form for bash (`poll_cache.py <dir> <max-age> -- gh api ...`, printing the cached or fresh stdout, caching exit 0 only). Route watch_rows, watch_mergeable and watch's check-runs read through it, and set the switch on queued_line's ci_gate call. Max age under watch's poll (scaled like nap). Failed reads are said on stderr as today. No config key. Use wait-pr-poll-cache's key form (full command and filter), never the path alone. watch_mergeable's pulls/<n> read stays uncached: it is keyed by PR number, not head, and a cached MERGEABLE would hide a conflict (merge.sh:2916-2920).

**Done when:**
- tests/watch_cache_test.sh: two watch --epic runs on one repo, with a stub gh that logs calls, log one open-PR list read and one check-runs read per PR head per poll between them; with the cache off they log two of each; with the cache removed the test goes red.
- Same file: a failed list read is not cached: the other watch reads again, and 'gh cannot list' is printed as today.
- Same file: a PR whose head moves between polls is read fresh for the new head.
- watch_opened_test.sh, stuck_work_watch_test.sh and the other tests that run watch pass unchanged.
- docs/reference-building.md's watch paragraph says concurrent watches share each poll's reads.
- Same file: watch_mergeable makes its own pulls/<n> read on every poll, cache on.
- A wait-pr and a watch on one head, cache on, each read their own output form and print what they print with the cache off.
- Two watches of a finished, unqueued head share the `ci_gate age` call's check-runs and status reads (merge.sh:2719, 2822).

---
kind: lead
status: later
epic: helpers-shared
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# You: say whether gh_cache is a sixth module under exception 3, and clear the patch-gate cache swap

The epic's Your part (board/epics/helpers-shared.md:30-33). report.py imports gh_cache (bin/lib/report.py:2), and exception 3 names five modules without it (board/hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md:284-287).
- **You:** (1) agree gh_cache is a sixth module under exception 3: its Go sits beside gh_cache.py under the comparison test, and the copy goes when report.py's does. Or have it bridged: gh_cache.py's get, put and Listing run the binary, one live implementation, and no comparison test. The lead recommends the sixth module: flow reads one cache file per PR, and a bridge would start the binary for each read.
- **You:** (2) clear non-fix-cache-binary on the board PR (the carve-out, HLD:486-491). It swaps the patch gate's cache call (bin/lib/board.sh:1781-1801) and changes no rule.
- Lead: write answer (1) into the scopes of go-gh-cache-files, go-gh-cache-records, go-report-merged and non-fix-cache-binary before any of them starts. On a bridge, go-gh-cache-files' comparison test becomes a test that gh_cache.py's calls reach the binary.

**Done when:**
- The user's answers to (1) and (2), quoted with their date, are in this story's file. The four stories' scopes say which reading of (1) they build.

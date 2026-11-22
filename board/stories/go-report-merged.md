---
kind: code
status: later
epic: helpers-shared
depends_on: [go-gh-cache-files, go-report-gh, go-report-text]
needs: go-gh-cache-files: ghcache.Listing and Day. go-report-gh: report.GH, SearchMerged and GHLimit. go-report-text: report.PRKey and MergeTime.
touches: [internal/report/merged.go, internal/report/merged_compare_test.go]
estimate_lines: 260
---

# report's merged_prs runs as Go over the Go gh cache

Needs Listing and Day from go-gh-cache-files, GH and SearchMerged from go-report-gh, and PRKey and MergeTime from go-report-text. internal/report: Github, MergedDays, MergedPR and MergedPRs, as bin/lib/report.py:241-290 has them. For each repo of the URLs, the Listing's hole is searched again first, then the days from one before its next. A list GHLimit long leaves its days as the hole, with the stderr line naming the cutoff. Items are saved with keep_days 120, and a mergedAt that is no date is kept. A comparison test runs report.py's merged_prs and the Go against one gh stub and one cache folder. It compares results and stderr byte for byte, and the cache file byte for byte after each run, over a cold cache, a warm one, a window before the cache's start, a stub list of exactly GHLimit PRs and a gh failure, plus the merged lists tests/features_test.sh and tests/flow_totals_test.sh give merged_prs (a PR merged in 2020, a PR gh could not read).

**Done when:**
- (1) The comparison test passes. (2) It goes red when MergedPRs alone skips the hole, when it alone saves no hole after a full list, and when report.py's merged_prs alone searches from next rather than the day before, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

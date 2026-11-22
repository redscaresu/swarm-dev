---
kind: code
status: later
epic: helpers-shared
depends_on: [go-report-text, go-report-fixes]
needs: go-report-text: report.PRKey, MergeTime and LocalDay. go-report-fixes: report.FixesPR.
touches: [internal/report/rework.go, internal/report/rework_compare_test.go]
estimate_lines: 220
---

# report's rework rules run as Go: rework_of, rework_from, rework_settled and rework_unknown

Needs PRKey, MergeTime and LocalDay from go-report-text, and FixesPR from go-report-fixes. internal/report, as bin/lib/report.py:97-98,142-173,292-307 has it: ReworkDays, ReleaseFiles, ReworkSettled (clock.Today minus 7 days), ReworkOf, ReworkFrom and ReworkUnknown. ReworkOf counts a later merge within 7 local days that FixesPR says fixes the PR, never a release PR, or an escaped finding dated 0 to 7 days after the merge day. A mergedAt that does not parse is left out and counted in one stderr line, which the Go returns for its caller to print. The escaped-outcome read carries `// outcome-scan: ok findings.tsv`. A comparison test, byte for byte, under SWARM_DASH_NOW and a fixed TZ: a fix on day 7 and on day 8, a merge before its fixer, a release PR, an escaped row on day -1, a bad finding date, a bad mergedAt, judged given and not, rework_from with 0000-00-00 and a bad date, plus tests/rework_test.sh's cases (a fix on day 3 and day 9, a merge local-day apart from UTC, a mergedAt that does not parse) and tests/model_fit_test.sh's rework_of call (:118-119).

**Done when:**
- (1) The comparison test passes. (2) It goes red when ReworkOf alone counts day 8, when it alone lets a release PR fix, and when report.py's rework_of alone counts an escaped row on day -1, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

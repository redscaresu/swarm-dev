---
kind: code
status: later
epic: helpers-shared
depends_on: [go-store-files, go-py-decode]
needs: go-store-files: Store.ReadFile. go-py-decode: pytext.DecodeReplace.
touches: [internal/report/findings.go, internal/report/findings_compare_test.go, docs/port/swarm-names.tsv:SWARM_FINDING_REVIEWERS row]
estimate_lines: 150
---

# report's findings readers run as Go: finding_rows and fixed_rows

Needs ReadFile from go-store-files and DecodeReplace from go-py-decode. internal/report: FindingRows(path, outcomes, width) and FixedRows, as bin/lib/report.py:57-67 has them. SWARM_FINDING_REVIEWERS is read first and is an error when unset (Python's KeyError), so a caller that does not pass it fails rather than dropping every row. A missing file gives no rows; a row under 4 columns is skipped; a 4-column row is fixed by unknown; only listed outcomes and reviewers are kept. The fifth-column read carries `// outcome-scan: ok findings.tsv`, as report.py:64 does. A comparison test, byte for byte, over tests/log_finding_test.sh's malformed cases, tests/recurring_kinds_test.sh's fixed rows, CRLF (newline="\n" keeps the \r), bad bytes and an unknown reviewer. SWARM_FINDING_REVIEWERS' row in docs/port/swarm-names.tsv gains the Go file.

**Done when:**
- (1) The comparison test passes. (2) It goes red when FindingRows alone defaults a 4-column row to declined, and when report.py's finding_rows alone drops the unknown reviewer, each shown on a worktree copy without .git. (3) A Go test shows FindingRows fails with SWARM_FINDING_REVIEWERS unset. (4) tests/port_swarm_names_test.sh passes, go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

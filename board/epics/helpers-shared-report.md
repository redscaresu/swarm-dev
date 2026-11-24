---
status: active
agreed: 2026-11-24
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-shared
depends_on: [foundation-exit, helpers-shared-base]
---

# report.py's functions run as Go beside the Python, under a comparison test

report.py's text, fixes, git, gh, findings, logs and rework functions exist as Go in internal/report.

A child of [helpers-shared](helpers-shared.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/report has a comparison test per part named in the stories: text, fixes, git, gh, findings, logs and rework. Each runs the Python and the Go over the same fixtures, the malformed cases among them, compares the output byte for byte, and fails when either side alone is changed.

**Stories:**
- [go-report-text](../stories/go-report-text.md)
- [go-report-fixes](../stories/go-report-fixes.md)
- [go-report-git](../stories/go-report-git.md)
- [go-report-gh](../stories/go-report-gh.md)
- [go-report-findings](../stories/go-report-findings.md)
- [go-report-logs](../stories/go-report-logs.md)
- [go-report-rework](../stories/go-report-rework.md)

**Out of scope:**
- report's merged listing, which needs gh_cache (helpers-shared-gh-cache)
- Switching any importer of report.py

**Your part:**
- None beyond the parent's: L2 patches.

**Areas:**
- go-report-text: [internal/report/doc.go, internal/report/text.go, internal/report/text_compare_test.go]
- go-report-fixes: [internal/report/fixes.go, internal/report/fixes_compare_test.go]
- go-report-git: [internal/iface/iface.go:Repo, internal/adapter/git/git.go:Run, internal/adapter/git/git_test.go, internal/report/git.go, internal/report/git_compare_test.go]
- go-report-gh: [internal/iface/iface.go:CodeHost, internal/adapter/gh/gh.go:Run, internal/adapter/gh/gh_test.go, internal/report/gh.go, internal/report/gh_compare_test.go]
- go-report-findings: [internal/report/findings.go, internal/report/findings_compare_test.go, docs/port/swarm-names.tsv:SWARM_FINDING_REVIEWERS row]
- go-report-logs: [internal/report/logs.go, internal/report/logs_compare_test.go, internal/layers/imports_test.go:allowedStd]
- go-report-rework: [internal/report/rework.go, internal/report/rework_compare_test.go]

---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/report/fixes.go, internal/report/fixes_compare_test.go]
estimate_lines: 240
---

# report's fix detection runs as Go: fixes_pr with its clause, verb and reach rules

internal/report: FixesPR and its parts (bin/lib/report.py:99-128): NOT_A_FIX clauses skipped, FIX verbs with hot, bug and quick prefixes, NEGATED just before the verb, FIX_REACH of 40 characters, the CLAUSE split. RE2 has no lookbehind, so pr_ref's (?<![\w./-]) and (?<![\w/#]) and CLAUSE's (?<=[.!?]) are matched by hand. Python's \w and \b take Unicode letters where RE2's take ASCII only; the Go matches Python on both. A comparison test runs report.py's fixes_pr and the Go over the same texts, byte for byte: 'Fixes #1 and doesn't fix #4', a URL, owner/repo#N, a bare #N in and out of the same repo, #12 against #123, a stacked-on clause, a sentence end, a verb 41 characters back, a Unicode letter before #N, and the PR bodies tests/rework_test.sh's gh stub gives (a fix of #1, a hotfix no build made). Detection logic: under about 200 lines of Go.

**Done when:**
- (1) The comparison test passes. (2) It goes red when the Go's hand-written lookbehind alone is dropped, when FIX_REACH alone becomes 41, and when report.py's NEGATED alone is changed, each shown on a worktree copy without .git. (3) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

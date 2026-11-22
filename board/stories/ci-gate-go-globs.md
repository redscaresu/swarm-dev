---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/globs.go, internal/merge/globs_test.go]
estimate_lines: 240
risk: high
---

# Go that nothing runs: the filter globs, covers, and the board-path matcher on_board

Adds glob, match and covers (ci_gate.py:507-540) and on_board (:160-174) to internal/merge.
- glob hands ?, + and [..] to the regex engine raw (:511-513). Go's RE2 reads some of those differently or not at all, and Python's own answer depends on its version: 3.11 and later read '*+' as possessive, older ones refuse it. The Go refuses a repeat after a repeat ('*+', '**+', '?+', '++') and any pattern RE2 cannot compile, as a bad-pattern error apart from Unread. pr_expected treats both as not read (:654); expected and main let the bad-pattern error end the run (:607, :1071). The PR names the 3.11 difference (contradiction 7).
- on_board takes the board's entries as a parameter, as bash passes them.

**Done when:**
- (1) glob and match cases, each want ci_gate.py's on python3 3.11 or later (the PR shows the version and the run): '*' stops at '/', '**' does not, '**/' is zero or more folders, '?' and '+' repeat what precedes, a [..] class, and a ! negation where the last match wins. (2) covers: branches, branches-ignore, tags only (false), paths, paths-ignore with every file ignored (false), files None (true: it fails closed) and f None (false). (3) 'docs/*+' and an unclosed '[' give the bad-pattern error, not Unread. (4) on_board's 10 paths of merge_base_moved_test.sh:186-193 over two boards given literally: 'stories/ epics/ hld/ Board.base .obsidian/ retros/*.md', and the same with a 'notes*/' prefix. (5) Each goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (6) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

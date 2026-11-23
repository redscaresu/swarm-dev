---
kind: code
status: blocked
epic: first-port
depends_on: [walk-calls]
needs: walk-calls (fileRecord's calls with their arguments, its comments, and constValue)
touches: [internal/layers/regexp_test.go, internal/layers/testdata/regexp/]
estimate_lines: 190
---

# A Go check fails a regexp or glob pattern built from a variable that is not passed through regexp.QuoteMeta

Needs walk-calls: fileRecord's calls with their arguments, its comments, and constValue. The go_check of docs/port/tests.tsv:87 for tests/loose_match_test.sh, which stays and keeps scanning the bash. internal/layers/ is a protected path (OWN_PROTECTED, bin/lib/board.sh:2546), so swarm.sh merge holds the PR for the user whatever its risk.
- A new file internal/layers/regexp_test.go, with fixture trees testdata/regexp/bad and testdata/regexp/clean, in time_test.go's pattern: exact findings written out (internal/layers/time_test.go:119).
- The rule covers every non-test .go file of the module. It judges the pattern argument of regexp.Compile, CompilePOSIX, MustCompile, MustCompilePOSIX, Match, MatchString and MatchReader, regexp/syntax.Parse, path.Match, filepath.Match and filepath.Glob (the first argument of each), and io/fs.Glob (the second). A glob is the Go form of the bash check's [[ == ]] shape.
- A pattern passes only when it is string literals, module constants and regexp.QuoteMeta calls, joined by + and parenthesised at will. A variable, a fmt.Sprintf or any other call fails.
- One of those functions used as a value fails (a selector record with called false), since the check cannot see its calls. An aliased import counts through its path. A dot import of regexp, regexp/syntax, path, path/filepath or io/fs fails, as in the time check, since the walk records no call behind it.
- A line that is right says so with a trailing `// loose-match: ok <reason>`, as in the bash. A bare ok with no reason does not count.
- Every top-level name in the file starts with regexp, so it cannot clash with go-check-deadlines' or go-check-starts' file in package layers once all three merge.
- TestRealTreeRegexp logs the rule and each call it allows, and fails unless it records internal/clock/clock.go:22, a raw literal, as one of them.
- No AGENTS.md change: AGENTS.md is trusted-go-port's alone (commands/plan-epic.md: no hot file in two stories). The rule is where AGENTS.md:258 sends a reader, go test -v's log, and each finding names the fix.

**Done when:**
- (1) TestRegexpFixtures asserts the exact finding lines on testdata/regexp/bad, one per shape: a variable, a + with a variable, Sprintf, filepath.Match, filepath.Glob, fs.Glob and syntax.Parse of a variable, an aliased import, a dot import, regexp.MustCompile used as a value, and the ok comment with no reason. It asserts none on testdata/regexp/clean: a literal, a const of the same package and of another, QuoteMeta of a variable, a + of those, and the ok comment with its reason. (2) TestRealTreeRegexp passes and logs internal/clock/clock.go:22 as allowed. (3) On a copy of the worktree without .git, each of these turns a test red, and the FAIL lines are in the PR body: the rule accepting any pattern; the ok comment accepted with no reason; QuoteMeta accepted only alone, not inside a +; the globs left unjudged; the real tree's calls dropped. (4) gofmt -l . prints nothing, and go vet ./... and go test ./... pass. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

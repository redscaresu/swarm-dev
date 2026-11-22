---
kind: code
status: later
epic: helpers-dropped-lines
depends_on: [go-report-git, dropped-lines-merged-parent]
needs: go-report-git (helpers-shared): the bounded git method on iface.Repo and adapter/git, which the reads call and the tests run real git through. dropped-lines-merged-parent (outside this epic): sides() as its fix leaves it.
touches: [internal/merge/dropped_reads.go, internal/merge/dropped_reads_test.go]
estimate_lines: 250
risk: high
---

# The dropped-lines git reads run through iface.Repo, each within 120 s

port: true; Go that nothing runs yet. It adds no iface or adapter method. It calls the Repo method go-report-git adds: run git with arguments, no stdin and a time bound, giving the exit code, stdout and stderr, and a result of its own past the bound. internal/merge/dropped_reads.go ports from bin/lib/dropped_lines.py, through that method only: the git wrapper (104-111: -C <repo>, -c core.quotePath=false, -c merge.conflictStyle=merge, 120 s on every call; stderr's first line after an ASCII strip, split at newline, carriage return or both); ancestor (113-117); automatic (119-126); sides (128-150, as dropped-lines-merged-parent leaves it; it returns whether the base side is the first parent, not a section); the blob read with its ls-tree check (233-242); the renames (244-257); named (259-267). A stop is an error holding the Python's text with git's line in it, which dropped-go-scan prints. Past the bound, or when git cannot start, the stop ends with the Go's own words, not Python's str(e) (see contradictions), and a test pins them. A read returns the blob's lines, not counts. Go tests build repos with git in t.TempDir(), with no user or system config, through adapter/git. Test files are outside internal/layers' walk (internal/layers/walk_test.go:54-57), and the non-test code imports no adapter. Names start with dropped or Dropped, as dropped-go-diff's. The PR body maps each case to the mutation that turns it red, with FAIL lines. The reviewer reads these Python functions against the Go, rule by rule (P6).

**Done when:**
- (1) A test with a fake iface.Repo that records each call sees every git call get the 120 s bound and the -C <repo> -c core.quotePath=false -c merge.conflictStyle=merge prefix; the fake's bound result and its start failure each give the stop text the test names. (2) go test ./internal/merge/ passes on real repos: sides on a merge of the base with its parents in either order; the exact stop text for an octopus, for neither parent on the base with no --merged, and for both on it; a --merged second parent whose first parent holds a base commit the branch lacks, scanned when it is git's own merge and stopped with its text when resolved by hand; a blob read of a file, of a path the commit lacks (absent) and of a directory's path (the stop); a rename and a copy each mapped to the old name; a stderr whose first line ends at a carriage return. Each expected stop text is copied from the format string it ports. (3) The PR body's table turns every case red on a worktree copy without .git, with FAIL lines; its mutations include dropping the merge-base --all check (the hand-resolved case) and passing no bound (test 1). (4) gofmt -l prints nothing, and go vet ./..., staticcheck ./..., errcheck ./... and go test ./internal/layers/ pass: internal/merge imports no module package but internal/iface and starts no process. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

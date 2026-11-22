---
kind: code
status: later
epic: helpers-dropped-lines
depends_on: [dropped-go-diff, dropped-go-counts, dropped-go-reads]
needs: dropped-go-diff (removed, clean, the 300-character cut); dropped-go-counts (the ordered multiset, owed, missing, extended); dropped-go-reads (the git wrapper, ancestor, automatic, sides, the blob and rename reads, the stop error).
touches: [internal/merge/dropped.go, internal/merge/dropped_test.go]
estimate_lines: 300
risk: high
---

# The dropped-lines check runs as Go from its arguments to its lines and exit code, with nothing calling it yet

port: true; Go that nothing runs yet. internal/merge/dropped.go is the whole check (bin/lib/dropped_lines.py:220-329,375-416), built on dropped-go-diff's removed, clean and cut, dropped-go-counts' multiset, owed, missing and extended, and dropped-go-reads' wrapper, sides and reads. It parses the arguments as the Python does: the usage stop for fewer than three, and for --own or --merged with nothing after; --merged and positional SHAs lowercased. The usage line is exactly `usage: swarm.sh _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>]... [<merge sha>...]`, the text dropped-lines-entry gives the Python. It lists the merges, checks --own's file at the head, and runs sides on every merge before any scan. It takes the merge base of base and head (none: no bound), and per merge reads the remerge diff with a/ and b/ prefixes and the merge base of its parents. Then it runs copies, gone, spare and owing (233-306) and the removed-line loop (308-329: whitespace-only lines judged on ASCII, sections, the own file skipped when the head lacks it). It returns one stop line and 2 before any line, the <sha7> <file>: <text> lines and 1, or nothing and 0. Go tests on real repos, as dropped-go-reads' are. Names start with dropped or Dropped. The PR body maps each case to the mutation that turns it red, with FAIL lines. The reviewer reads scan and the main block against the Go, rule by rule (P6).

**Done when:**
- (1) go test ./internal/merge/ passes on real repos, with the lines and exit codes tests/dropped_lines_test.sh gives for the same shapes: an older merge that dropped a base line and a newer clean one (dropped_lines_test.sh:67-73); a file the PR renamed (145-150); an octopus (241); a merged parent's merge with and without --merged (275-278); a line put back by a later commit (371); a line the head extends (457); fewer than three arguments, --merged with no SHA and --own with no path (the usage line above); an unreadable range (its stop with git's line); and a merge that drops a line before a later octopus, which prints the stop and no line. (2) The PR body's table turns every case red on a worktree copy without .git, with FAIL lines; its mutations include scanning each merge as soon as its sides are read (the last case), gone() always false, the own file skipped though the head has it, and the blank check on Unicode whitespace. (3) gofmt -l prints nothing, and go vet ./..., staticcheck ./..., errcheck ./... and go test ./internal/layers/ pass. (4) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

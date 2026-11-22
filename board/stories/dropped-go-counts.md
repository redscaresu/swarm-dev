---
kind: code
status: later
epic: helpers-dropped-lines
depends_on: []
touches: [internal/merge/dropped_counts.go, internal/merge/dropped_counts_test.go]
estimate_lines: 270
risk: high
---

# The copies a merge owes, the lines the head has not put back, and the extends rule are Go

port: true; Go that nothing runs yet. internal/merge/dropped_counts.go ports from bin/lib/dropped_lines.py: an ordered multiset of lines, Python's Counter as the file uses it (insertion order kept; subtraction keeps the left side's order and positive counts; union takes the larger count: 241,289-293); owed (213-218); missing (331-344, with an unbounded need where the merge base of base and head has no such file: 304); extends (346-353: words split on ASCII whitespace only, space, tab, newline, vertical tab, form feed and carriage return, as bytes.split() does, not bytes.Fields; the head line's words hold the line's in order, and the line's words are more than half the head line's); extended (355-373: EXTENDED_WORDS 3, a pool per head file, every found text taken out of it, the first spare head line in the file's order taken). Lines stay []byte. Standard library only. Names start with dropped or Dropped, as dropped-go-diff's. The PR body maps each case to the mutation that turns it red, with FAIL lines. The reviewer reads the five Python pieces against the Go, rule by rule (P6).

**Done when:**
- (1) go test ./internal/merge/ passes with cases: owed for a line new to the file that both sides added (the larger side) and for one the merge base had (the sum less the merge base's); missing keeping the newest entries, in merge order, and every entry under an unbounded need; extends true with words added and with spacing changed, false with a word taken out, changed or moved, false at exactly half the head line's words, false where U+00A0 joins two words, true where a vertical tab separates them; extended taking the first spare line in head order where two extend one line, and leaving the second for the next entry; a two-word line never cleared; a text any entry has never standing for another; subtraction keeping the left side's order. (2) The PR body's table turns every case red on a worktree copy without .git, with FAIL lines; its mutations include bytes.Fields in extends, the pool ranged in sorted order, owed always summing, missing keeping the oldest entries, and subtraction in sorted order. (3) gofmt -l prints nothing, and go vet ./..., staticcheck ./..., errcheck ./... and go test ./internal/layers/ pass. (4) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

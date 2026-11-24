package merge

import (
	"bytes"
	"fmt"
	"slices"
	"strings"
	"testing"
)

// Every want below is what dropped_lines.py's own Counter, owed, missing, extends and extended
// give for the same input, run by hand with python3 on 2026-11-24; the PR that added this file has
// the runs.

// droppedSplit is s's lines, split at each newline, as a blob read gives them.
func droppedSplit(s string) [][]byte {
	return bytes.Split([]byte(s), []byte("\n"))
}

// droppedListed is c's lines in its order, each with its copies, as "line×n" joined by " | ".
func droppedListed(c *droppedCounts) string {
	var parts []string
	for _, line := range c.held() {
		parts = append(parts, fmt.Sprintf("%s×%d", line, c.of(line)))
	}
	return strings.Join(parts, " | ")
}

// If the multiset sorted its lines, summed a union or kept a line with no copies left, a want here
// would not match.
func TestDroppedCounts(t *testing.T) {
	rows := []struct {
		name string
		got  func() *droppedCounts
		want string
	}{
		{"count keeps the order of each line's first copy",
			func() *droppedCounts { return droppedCount(droppedSplit("b\na\nb")) }, "b×2 | a×1"},
		{"subtraction keeps the left side's order and lines with a copy left",
			func() *droppedCounts {
				return droppedCount(droppedSplit("z\na\nm\na\nq")).minus(droppedCount(droppedSplit("a\na\na\nq\nx")))
			}, "z×1 | m×1"},
		{"subtraction from a file the commit does not have",
			func() *droppedCounts { return (*droppedCounts)(nil).minus(droppedCount(droppedSplit("a"))) }, ""},
		{"subtraction of a file the commit does not have",
			func() *droppedCounts { return droppedCount(droppedSplit("b\na")).minus(nil) }, "b×1 | a×1"},
		{"union takes the larger count, the left side's lines first, then the right's new ones",
			func() *droppedCounts {
				return droppedCount(droppedSplit("q\nb")).union(droppedCount(droppedSplit("b\nb\nz\na")))
			}, "q×1 | b×2 | z×1 | a×1"},
		{"union with a file the commit does not have",
			func() *droppedCounts { return droppedCount(droppedSplit("b\na")).union(nil) }, "b×1 | a×1"},
		{"union into a file the commit does not have",
			func() *droppedCounts { return (*droppedCounts)(nil).union(droppedCount(droppedSplit("b\na"))) }, "b×1 | a×1"},
	}
	for _, r := range rows {
		t.Run(r.name, func(t *testing.T) {
			if got := droppedListed(r.got()); got != r.want {
				t.Errorf("got %q, want %q", got, r.want)
			}
		})
	}
}

// If owed always summed, or took the larger side's copies whenever the merge base has the line, a
// want here would not match.
func TestDroppedOwed(t *testing.T) {
	rows := []struct {
		name             string
		base, side, root int
		want             int
	}{
		{"a line new to the file that both sides added: the base side's, the larger", 2, 1, 0, 2},
		{"a line new to the file that both sides added: the PR side's, the larger", 1, 3, 0, 3},
		{"a line the merge base had: the sum less the merge base's", 2, 2, 1, 3},
	}
	for _, r := range rows {
		t.Run(r.name, func(t *testing.T) {
			if got := droppedOwed(r.base, r.side, r.root); got != r.want {
				t.Errorf("droppedOwed(%d, %d, %d) = %d, want %d", r.base, r.side, r.root, got, r.want)
			}
		})
	}
}

// droppedIn is an entry of the head's file named file, for text, printing line, with no spare lines.
func droppedIn(file, text, line string) droppedEntry {
	return droppedEntry{file: droppedHeadFile{headHas: true, name: file}, text: []byte(text), line: line}
}

// droppedOwes is e owing need copies with the head holding held.
func droppedOwes(e droppedEntry, need, held int) droppedEntry {
	e.need, e.held = need, held
	return e
}

// droppedLinesOf is the line each entry prints, in order.
func droppedLinesOf(entries []droppedEntry) []string {
	var lines []string
	for _, e := range entries {
		lines = append(lines, e.line)
	}
	return lines
}

// If missing kept the oldest entries, left them newest first, ignored no bound, took a later merge's
// smaller need over an earlier one's larger, ignored the copies the head holds, or keyed entries by
// text alone or by name without its kind, a want here would not match.
func TestDroppedMissing(t *testing.T) {
	unbounded := func(e droppedEntry) droppedEntry {
		e.unbounded, e.held = true, 5
		return e
	}
	// The file the head has no name for, under the same name as the head's "f".
	notInHead := droppedEntry{file: droppedHeadFile{name: "f"}, text: []byte("lost line"), line: "m2 f: lost line", need: 1}
	rows := []struct {
		name  string
		found []droppedEntry
		want  []string
	}{
		{"the newest entries, in merge order",
			[]droppedEntry{
				droppedOwes(droppedIn("f", "lost line", "m1 f: lost line"), 2, 0),
				droppedOwes(droppedIn("f", "lost line", "m2 f: lost line"), 2, 0),
				droppedOwes(droppedIn("f", "lost line", "m3 f: lost line"), 2, 0),
			},
			[]string{"m2 f: lost line", "m3 f: lost line"}},
		{"every entry under an unbounded need",
			[]droppedEntry{
				unbounded(droppedIn("f", "lost line", "m1 f: lost line")),
				unbounded(droppedIn("f", "lost line", "m2 f: lost line")),
			},
			[]string{"m1 f: lost line", "m2 f: lost line"}},
		{"the most any merge owes, not the last merge's",
			[]droppedEntry{
				droppedOwes(droppedIn("f", "lost line", "m1 f: lost line"), 2, 0),
				droppedOwes(droppedIn("f", "lost line", "m2 f: lost line"), 1, 0),
			},
			[]string{"m1 f: lost line", "m2 f: lost line"}},
		{"a copy the head holds is put back",
			[]droppedEntry{
				droppedOwes(droppedIn("f", "lost line", "m1 f: lost line"), 2, 1),
				droppedOwes(droppedIn("f", "lost line", "m2 f: lost line"), 2, 1),
			},
			[]string{"m2 f: lost line"}},
		{"one key per head file, and a name the head lacks is its own key",
			[]droppedEntry{
				droppedOwes(droppedIn("f", "lost line", "m1 f: lost line"), 1, 0),
				notInHead,
				droppedOwes(droppedIn("g", "lost line", "m3 g: lost line"), 1, 0),
			},
			[]string{"m1 f: lost line", "m2 f: lost line", "m3 g: lost line"}},
	}
	for _, r := range rows {
		t.Run(r.name, func(t *testing.T) {
			if got := droppedLinesOf(droppedMissing(r.found)); !slices.Equal(got, r.want) {
				t.Errorf("got %q, want %q", got, r.want)
			}
		})
	}
}

// If extends split on Unicode spaces (bytes.Fields) or on spaces and tabs alone, ignored the words'
// order or which words the head line holds, or let a line of half the head line's words through, a
// want here would not match.
func TestDroppedExtends(t *testing.T) {
	rows := []struct {
		name, text, head string
		want             bool
	}{
		{"words added", "alpha beta gamma", "alpha new beta gamma", true},
		{"spacing changed", "alpha beta  gamma", "\talpha   beta gamma ", true},
		{"a word taken out", "alpha beta gamma delta", "alpha gamma delta", false},
		{"a word changed", "alpha beta gamma", "alpha BETA gamma", false},
		{"a word moved", "alpha beta gamma", "beta alpha gamma", false},
		{"exactly half the head line's words", "alpha beta gamma", "alpha beta gamma one two three", false},
		{"just over half the head line's words", "alpha beta gamma", "alpha beta gamma one two", true},
		{"U+00A0 joins two words", "alpha beta gamma", "alpha\u00a0beta gamma", false},
		{"a vertical tab separates two words", "alpha beta gamma", "alpha\vbeta gamma", true},
		{"a form feed, a carriage return and a newline separate words", "alpha beta gamma delta", "alpha\fbeta\rgamma\ndelta", true},
	}
	for _, r := range rows {
		t.Run(r.name, func(t *testing.T) {
			if got := droppedExtends([]byte(r.text), []byte(r.head)); got != r.want {
				t.Errorf("droppedExtends(%q, %q) = %v, want %v", r.text, r.head, got, r.want)
			}
		})
	}
}

// If extended ranged a pool in sorted order, left a taken copy in it, cleared a line of two words,
// let a dropped text stand for another, shared one pool between files, took a file's pool from its
// last entry, or changed the entries' spare lines, a want here would not match.
func TestDroppedExtended(t *testing.T) {
	// spare gives e the spare lines in lines, one to a line; "" is none.
	spare := func(e droppedEntry, lines string) droppedEntry {
		e.spare = droppedCount(nil)
		if lines != "" {
			e.spare = droppedCount(droppedSplit(lines))
		}
		return e
	}
	rows := []struct {
		name  string
		found []droppedEntry
		left  []int // the entries of found that missing kept
		want  []string
	}{
		{"the first spare line in head order, the second left for the next entry",
			[]droppedEntry{
				spare(droppedIn("f", "b c d", "m1 f: b c d"), "z b c d\nb c d e"),
				spare(droppedIn("f", "c d e", "m1 f: c d e"), "z b c d\nb c d e"),
			},
			[]int{0, 1}, nil},
		{"a head line taken stands for one copy",
			[]droppedEntry{
				spare(droppedIn("f", "b c d", "m1 f: b c d"), "z b c d"),
				spare(droppedIn("f", "b c d", "m2 f: b c d"), "z b c d"),
			},
			[]int{0, 1}, []string{"m2 f: b c d"}},
		{"a two-word line is never cleared",
			[]droppedEntry{spare(droppedIn("f", "exit 1", "m1 f: exit 1"), "exit 1 now")},
			[]int{0}, []string{"m1 f: exit 1"}},
		{"a text any entry has never stands for another",
			[]droppedEntry{
				spare(droppedIn("f", "b c d", "m1 f: b c d"), "b c d e"),
				spare(droppedIn("f", "b c d e", "m1 f: b c d e"), "b c d e"),
			},
			[]int{0}, []string{"m1 f: b c d"}},
		{"a head line in another file never clears a line",
			[]droppedEntry{
				spare(droppedIn("g", "other line here", "m1 g: other line here"), "z b c d"),
				spare(droppedIn("f", "b c d", "m1 f: b c d"), ""),
			},
			[]int{1}, []string{"m1 f: b c d"}},
		{"a file's pool is its first entry's spare lines",
			[]droppedEntry{
				spare(droppedIn("f", "b c d", "m1 f: b c d"), "z b c d"),
				spare(droppedIn("f", "q r s", "m1 f: q r s"), ""),
			},
			[]int{0}, nil},
	}
	for _, r := range rows {
		t.Run(r.name, func(t *testing.T) {
			var left []droppedEntry
			for _, i := range r.left {
				left = append(left, r.found[i])
			}
			before := make([]string, len(r.found))
			for i, e := range r.found {
				before[i] = droppedListed(e.spare)
			}
			if got := droppedExtended(left, r.found); !slices.Equal(got, r.want) {
				t.Errorf("got %q, want %q", got, r.want)
			}
			for i, e := range r.found {
				if after := droppedListed(e.spare); after != before[i] {
					t.Errorf("entry %d's spare lines went from %q to %q", i, before[i], after)
				}
			}
		})
	}
}

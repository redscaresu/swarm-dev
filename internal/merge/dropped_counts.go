package merge

// This file holds the counting rules of the dropped-lines check, ported from bin/lib/dropped_lines.py:
// the ordered multiset of a file's lines that the Python's Counter is there, owed, missing, extends
// and extended. Nothing runs it yet.

import (
	"bytes"
	"slices"
)

// The extends rule's two numbers (dropped_lines.py:88-91).
const (
	// droppedExtendedWords is the fewest words a printed line needs for a longer head line to clear
	// it: a `}` or an `exit 1` is in many lines a PR writes for itself (`} else {`, `|| exit 1`).
	droppedExtendedWords = 3
	// droppedExtendedShare is the share of a head line's words that a printed line's words must be
	// more than for that head line to clear it, so the head line is the printed one with words added.
	droppedExtendedShare = 0.5
)

// droppedCounts is an ordered multiset of a file's lines: Python's Counter as dropped_lines.py uses
// it. Each line keeps the place its first copy was added at, and a line it does not hold has no
// copies. It keeps the slices it is given and never writes to them. No count goes below 0, so
// Counter's handling of negative counts never applies.
//
// A nil *droppedCounts is a file the commit does not have (the Python's None). Its reads give no
// lines and no copies, as the Python's `got or Counter()` does.
type droppedCounts struct {
	lines  [][]byte       // each line held, in the order its first copy was added
	copies map[string]int // each held line's copies, keyed by the line's bytes as they are, never decoded
}

// droppedCount counts lines as Counter(blob.split(b"\n")) does (dropped_lines.py:242): one entry per
// distinct line, in the order its first copy comes.
func droppedCount(lines [][]byte) *droppedCounts {
	c := &droppedCounts{copies: map[string]int{}}
	for _, line := range lines {
		c.add(line, 1)
	}
	return c
}

// add gives line n more copies, placing it last when c did not hold it.
func (c *droppedCounts) add(line []byte, n int) {
	key := string(line)
	if _, held := c.copies[key]; !held {
		c.lines = append(c.lines, line)
	}
	c.copies[key] += n
}

// held is the lines c holds, in its order, a line taken down to no copies included, as iterating a
// Counter gives them.
func (c *droppedCounts) held() [][]byte {
	if c == nil {
		return nil
	}
	return c.lines
}

// has reports whether c holds line, even with no copies left, as Python's `line in counter` does.
func (c *droppedCounts) has(line []byte) bool {
	if c == nil {
		return false
	}
	_, held := c.copies[string(line)]
	return held
}

// of is line's copies in c: 0 for a line c does not hold, as counter[line] gives.
func (c *droppedCounts) of(line []byte) int {
	if c == nil {
		return 0
	}
	return c.copies[string(line)]
}

// union is c | o, as `base |= got` and `top |= c` take it (dropped_lines.py:291-292,319-320): each
// line's larger count, c's lines in c's order and then o's new ones in o's order, and only lines with
// a copy.
func (c *droppedCounts) union(o *droppedCounts) *droppedCounts {
	out := droppedCount(nil)
	for _, line := range c.held() {
		if n := max(c.of(line), o.of(line)); n > 0 {
			out.add(line, n)
		}
	}
	for _, line := range o.held() {
		if n := o.of(line); !c.has(line) && n > 0 {
			out.add(line, n)
		}
	}
	return out
}

// minus is c - o, as spare takes it (dropped_lines.py:294): c's lines in c's order, each with its
// copies less o's, and only those with a copy left.
func (c *droppedCounts) minus(o *droppedCounts) *droppedCounts {
	out := droppedCount(nil)
	for _, line := range c.held() {
		if n := c.of(line) - o.of(line); n > 0 {
			out.add(line, n)
		}
	}
	return out
}

// clone is Counter(c) (dropped_lines.py:385): every line c holds, in its order, with its copies.
func (c *droppedCounts) clone() *droppedCounts {
	out := droppedCount(nil)
	for _, line := range c.held() {
		out.add(line, c.of(line))
	}
	return out
}

// drop takes line out of c, its place too, as counter.pop(line, None) does (dropped_lines.py:387).
func (c *droppedCounts) drop(line []byte) {
	if !c.has(line) {
		return
	}
	delete(c.copies, string(line))
	c.lines = slices.DeleteFunc(c.lines, func(held []byte) bool { return bytes.Equal(held, line) })
}

// take takes one copy of line, which c holds with a copy left; the line keeps its place
// (dropped_lines.py:396).
func (c *droppedCounts) take(line []byte) {
	c.copies[string(line)]--
}

// extending is the first line of c, in c's order, with a copy left that extends text, and whether
// there is one (dropped_lines.py:391-392). There is none for a text of fewer than
// droppedExtendedWords words.
func (c *droppedCounts) extending(text []byte) ([]byte, bool) {
	if len(droppedWords(text)) < droppedExtendedWords {
		return nil, false
	}
	for _, line := range c.held() {
		if c.of(line) > 0 && droppedExtends(text, line) {
			return line, true
		}
	}
	return nil, false
}

// droppedOwed is the copies of a line that a merge of two sides keeps, from the base side's copies
// (base), the PR side's (side) and their merge base's (root) (dropped_lines.py:214-219). It is the
// sum less the merge base's. For a line new to the file that both sides added, such as a squash and
// its own commit, it is the larger side's instead. With the line in the merge base, a new copy on
// each side can be two additions, so the sum stands.
func droppedOwed(base, side, root int) int {
	if root == 0 && base > 0 && side > 0 {
		return max(base, side)
	}
	return base + side - root
}

// droppedHeadFile is the file part of an entry's head key (dropped_lines.py:306): the head's own name
// for the file, or, where the head has the file under no name, the merge's name for it. The two
// kinds never match, even with the same name.
type droppedHeadFile struct {
	headHas bool   // name is the head's own name for the file
	name    string // the name's bytes as they are; a string so the file can key a map
}

// droppedHeadKey is an entry's head key (dropped_lines.py:306): its head file and its text.
type droppedHeadKey struct {
	file droppedHeadFile
	text string // the line's bytes as they are
}

// droppedEntry is one copy of a line that a merge printed, as scan returns it
// (dropped_lines.py:353): its head file and text, the copies the head owes and holds, the head
// file's spare lines and the line it prints.
type droppedEntry struct {
	file droppedHeadFile
	text []byte // the dropped line
	// need is the copies of text the head owes the merge. It is read only while bounded.
	need int
	// unbounded: there is no bound, as the merge base of base and head has no such file
	// (dropped_lines.py:305).
	unbounded bool
	held      int            // the copies of text the head's file holds
	spare     *droppedCounts // the head file's lines beyond the most that base or that merge base holds
	line      string         // `<merge sha7> <file>: <text>`, as it prints
}

// key is e's head key.
func (e droppedEntry) key() droppedHeadKey {
	return droppedHeadKey{file: e.file, text: string(e.text)}
}

// droppedOwing is what the head owes one head key, the most any merge owes it: a count of copies, or
// no bound.
type droppedOwing struct {
	copies    int
	unbounded bool
}

// droppedMissing is the entries of found, one per printed copy in merge order, that the head has not
// put back (dropped_lines.py:355-368). Per head key, it keeps as many as the head holds fewer copies
// than the most any merge owes. Those are the newest merges' entries, since a commit that puts a line
// back comes after the merge that dropped it, and they stay in merge order, oldest first. Under no
// bound it keeps every entry of the key. Where entries of one key hold different counts, the last
// one's counts, as the Python's dict takes it.
func droppedMissing(found []droppedEntry) []droppedEntry {
	owe := map[droppedHeadKey]droppedOwing{}
	for _, e := range found {
		k := e.key()
		o, seen := owe[k]
		if !seen {
			o.copies = e.need
		}
		o.copies = max(o.copies, e.need)
		o.unbounded = o.unbounded || e.unbounded
		owe[k] = o
	}
	short := map[droppedHeadKey]int{}
	for _, e := range found {
		k := e.key()
		short[k] = owe[k].copies - e.held
	}
	var left []droppedEntry
	for i := len(found) - 1; i >= 0; i-- {
		k := found[i].key()
		if owe[k].unbounded {
			left = append(left, found[i])
			continue
		}
		if short[k] > 0 {
			short[k]--
			left = append(left, found[i])
		}
	}
	slices.Reverse(left)
	return left
}

// droppedSpace reports whether r is one of the bytes Python's bytes.split() with no argument splits
// on: ASCII whitespace alone (space, tab, newline, vertical tab, form feed and carriage return). A
// non-ASCII space such as U+00A0 joins two words, where bytes.Fields would split them.
func droppedSpace(r rune) bool {
	switch r {
	case ' ', '\t', '\n', '\v', '\f', '\r':
		return true
	}
	return false
}

// droppedWords is line's words, as bytes.split() gives them. FieldsFunc reads runes, but no byte of a
// multi-byte or invalid sequence reads as an ASCII rune, so the split is the same on any bytes.
func droppedWords(line []byte) [][]byte {
	return bytes.FieldsFunc(line, droppedSpace)
}

// droppedExtends reports whether head is text with words added or its spacing changed
// (dropped_lines.py:370-377): head's words hold every word of text in the same order, and text's
// words are more than droppedExtendedShare of head's.
func droppedExtends(text, head []byte) bool {
	wanted, words := droppedWords(text), droppedWords(head)
	if float64(len(wanted)) <= droppedExtendedShare*float64(len(words)) {
		return false
	}
	rest := words
	for _, word := range wanted {
		at := slices.IndexFunc(rest, func(w []byte) bool { return bytes.Equal(w, word) })
		if at < 0 {
			return false
		}
		rest = rest[at+1:]
	}
	return true
}

// droppedExtended is the lines of left, missing's entries of found, that no line the head added
// extends (dropped_lines.py:379-397), in left's order. Each head file has one pool: the spare lines
// of the first entry of found in that file, less every text an entry of found has, so a dropped
// line's own copies never stand for another. In left's order, an entry of droppedExtendedWords words
// or more takes one copy of the first line of its pool, in the pool's order, with a copy left that
// extends it, and does not print. It does not change found's spare lines.
func droppedExtended(left, found []droppedEntry) []string {
	pools := map[droppedHeadFile]*droppedCounts{}
	for _, e := range found {
		if _, made := pools[e.file]; !made {
			pools[e.file] = e.spare.clone()
		}
	}
	for _, e := range found {
		pools[e.file].drop(e.text)
	}
	var lines []string
	for _, e := range left {
		pool := pools[e.file]
		head, ok := pool.extending(e.text)
		if !ok {
			lines = append(lines, e.line)
			continue
		}
		pool.take(head)
	}
	return lines
}

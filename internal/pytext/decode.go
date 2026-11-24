// Package pytext turns bytes into text the way the Python helpers do, so a port reads a file or a
// program's output into the same string the helper read.
//
// The Python reads bad UTF-8 with errors="replace" (bin/lib/report.py's gh call,
// bin/lib/touches_rows.py's front, the findings and declines readers) and with errors="ignore"
// (report.py's log_lines). DecodeReplace and DecodeIgnore give what bytes.decode("utf-8", errors)
// gives on the same bytes. Text mode's newline translation, which open() and subprocess's text mode
// add on top, is not theirs: a caller that needs it does it after.
package pytext

import (
	"strings"
	"unicode/utf8"
)

// replacement is what errors="replace" puts in place of each maximal invalid subsequence.
const replacement = "\uFFFD"

// asciiEnd is the first byte that is not ASCII; every byte below it is a character of its own.
const asciiEnd = 0x80

// The range a continuation byte takes, past the second byte of a sequence.
const (
	contLo = 0x80
	contHi = 0xBF
)

// lead is a range of lead bytes and what follows them in well-formed UTF-8: conts continuation
// bytes, the first of which lies in lo..hi and the rest in contLo..contHi.
type lead struct {
	first, last byte
	conts       int
	lo, hi      byte
}

// leads is Table 3-7 of the Unicode Standard, Well-Formed UTF-8 Byte Sequences, which CPython's
// decoder follows. The narrow second-byte ranges are what shut out overlong forms (E0, F0),
// encoded surrogates (ED) and code points above U+10FFFF (F4). A byte in no row (80..C1, F5..FF)
// starts no sequence.
var leads = []lead{
	{first: 0xC2, last: 0xDF, conts: 1, lo: contLo, hi: contHi},
	{first: 0xE0, last: 0xE0, conts: 2, lo: 0xA0, hi: contHi},
	{first: 0xE1, last: 0xEC, conts: 2, lo: contLo, hi: contHi},
	{first: 0xED, last: 0xED, conts: 2, lo: contLo, hi: 0x9F},
	{first: 0xEE, last: 0xEF, conts: 2, lo: contLo, hi: contHi},
	{first: 0xF0, last: 0xF0, conts: 3, lo: 0x90, hi: contHi},
	{first: 0xF1, last: 0xF3, conts: 3, lo: contLo, hi: contHi},
	{first: 0xF4, last: 0xF4, conts: 3, lo: contLo, hi: 0x8F},
}

// DecodeReplace is b.decode("utf-8", "replace"): valid UTF-8 as it is, and one U+FFFD for each
// maximal invalid subsequence, as CPython cuts them. Go's own conversions differ:
// strings.ToValidUTF8 gives one per run of bad bytes, and ranging over a string one per bad byte.
func DecodeReplace(b []byte) string { return decode(b, replacement) }

// DecodeIgnore is b.decode("utf-8", "ignore"): valid UTF-8 as it is, with every invalid byte
// dropped.
func DecodeIgnore(b []byte) string { return decode(b, "") }

// decode copies the valid sequences of b and writes repl in place of each maximal invalid
// subsequence.
func decode(b []byte, repl string) string {
	if utf8.Valid(b) {
		return string(b)
	}
	var out strings.Builder
	out.Grow(len(b))
	for len(b) > 0 {
		n, ok := next(b)
		if ok {
			out.Write(b[:n])
		} else {
			out.WriteString(repl)
		}
		b = b[n:]
	}
	return out.String()
}

// next is the length of the sequence b starts with, and whether it is well-formed. A sequence that
// is not is its maximal subpart: the lead byte and the continuation bytes that fit it, up to the
// first byte that does not, which starts the next sequence. A lead byte in no row of leads is a
// subpart of one byte.
func next(b []byte) (int, bool) {
	if b[0] < asciiEnd {
		return 1, true
	}
	l, ok := leadOf(b[0])
	if !ok {
		return 1, false
	}
	lo, hi := l.lo, l.hi
	for i := 1; i <= l.conts; i++ {
		if i >= len(b) || b[i] < lo || b[i] > hi {
			return i, false
		}
		lo, hi = contLo, contHi
	}
	return l.conts + 1, true
}

// leadOf is the row of leads that c starts, if any.
func leadOf(c byte) (lead, bool) {
	for _, l := range leads {
		if c >= l.first && c <= l.last {
			return l, true
		}
	}
	return lead{}, false
}

package trust

import (
	"bytes"
	"encoding/json"
	"errors"
	"unicode/utf8"
)

// maxDepth is how deep arrays and objects may nest. It is encoding/json's own limit, so the
// decoder never meets text deeper than it reads. Text that nests deeper is taken as Python's
// RecursionError, which require_trusted.py does not catch, so it exits 1.
const maxDepth = 10000

var (
	// errNotJSON is text that json.load raises ValueError on, which require_trusted.py catches.
	errNotJSON = errors.New("not JSON as Python's json module reads it")
	// errTooDeep is text that nests deeper than maxDepth before any syntax error.
	errTooDeep = errors.New("nested deeper than maxDepth")
)

// nonFinite maps each of the literals Python's json reads as a float, and encoding/json does not
// read at all, to null. The rule asks of a value only "an object?" and "exactly true?", and null
// answers both as NaN does.
var nonFinite = [][]byte{[]byte("NaN"), []byte("Infinity"), []byte("-Infinity")}

// nullText replaces each nonFinite literal.
var nullText = []byte("null")

// noMatchEscape replaces a lone surrogate escape in a string. Python keeps a lone surrogate in
// the key, which no UTF-8 root equals; encoding/json would read it as U+FFFD, which one could.
// NUL is in no root, since an argument cannot hold it.
var noMatchEscape = []byte(`\u0000`)

// read returns the value in data as Python's json.load(open(config)) reads it in a UTF-8 locale:
// an object is a map[string]any whose duplicate keys keep the last, and a number a json.Number.
// It returns errNotJSON where Python raises ValueError and errTooDeep where it would recurse past
// maxDepth.
func read(data []byte) (any, error) {
	if !utf8.Valid(data) {
		return nil, errNotJSON
	}
	text, open, deepAt := scan(data)
	if deepAt >= 0 {
		// Python reads as far as the opener that goes too deep; text that is broken before it
		// raises ValueError there. A null in the opener's place, with every container closed,
		// is valid exactly when nothing before it is broken.
		if json.Valid(closeAll(text[:deepAt], open)) {
			return nil, errTooDeep
		}
		return nil, errNotJSON
	}
	if !json.Valid(text) {
		return nil, errNotJSON
	}
	dec := json.NewDecoder(bytes.NewReader(text))
	dec.UseNumber() // 1e400 and 5000 digits are JSON to Python; a float64 cannot hold them
	v, err := value(dec)
	if err != nil {
		return nil, errNotJSON
	}
	return v, nil
}

// scan copies data, outside strings rewriting each nonFinite literal to null and inside them each
// lone surrogate escape to noMatchEscape. It counts the depth as it goes: when an opener would
// nest past maxDepth, it stops and returns the copy so far, the openers still open, and the
// offset in the copy where the opener goes. deepAt is -1 when the text stays within maxDepth.
func scan(data []byte) (text, open []byte, deepAt int) {
	text = make([]byte, 0, len(data))
	for i := 0; i < len(data); {
		switch c := data[i]; {
		case c == '"':
			i = stringEnd(data, i+1, &text)
		case c == '[' || c == '{':
			if len(open) == maxDepth {
				return text, open, len(text)
			}
			open = append(open, c)
			text = append(text, c)
			i++
		case c == ']' || c == '}':
			if len(open) > 0 {
				open = open[:len(open)-1]
			}
			text = append(text, c)
			i++
		default:
			if n := nonFiniteAt(data[i:]); n > 0 {
				text = append(text, nullText...)
				i += n
				continue
			}
			text = append(text, c)
			i++
		}
	}
	return text, open, -1
}

// nonFiniteAt is the length of the nonFinite literal rest starts with, or 0.
func nonFiniteAt(rest []byte) int {
	for _, lit := range nonFinite {
		if bytes.HasPrefix(rest, lit) {
			return len(lit)
		}
	}
	return 0
}

// stringEnd appends to text the string that opens at data[start-1] and returns the offset just
// past its closing quote, or len(data) when it never closes. A lone surrogate escape is appended
// as noMatchEscape; a high surrogate escape followed by a low one is a pair, copied as it is.
func stringEnd(data []byte, start int, text *[]byte) int {
	*text = append(*text, '"')
	for i := start; i < len(data); {
		switch c := data[i]; {
		case c == '"':
			*text = append(*text, c)
			return i + 1
		case c == '\\':
			n := escapeLen(data[i:])
			if n == len(noMatchEscape) && isLoneSurrogate(data[i:]) {
				*text = append(*text, noMatchEscape...)
			} else {
				*text = append(*text, data[i:i+n]...)
			}
			i += n
		default:
			*text = append(*text, c)
			i++
		}
	}
	return len(data)
}

// escapeLen is how many bytes of rest, which starts with a backslash, the escape takes: 12 for a
// surrogate pair, 6 for any other \u escape, and 2 (or 1 at the end) for the rest. A malformed
// escape is copied for json.Valid to refuse.
func escapeLen(rest []byte) int {
	if u, ok := hexEscape(rest); ok {
		if isHigh(u) {
			if low, ok := hexEscape(rest[6:]); ok && isLow(low) {
				return 12
			}
		}
		return 6
	}
	return min(2, len(rest))
}

// isLoneSurrogate reports whether rest starts with a \u escape of a surrogate that escapeLen did
// not pair.
func isLoneSurrogate(rest []byte) bool {
	u, ok := hexEscape(rest)
	return ok && (isHigh(u) || isLow(u))
}

// hexEscape reads the \uXXXX escape rest starts with.
func hexEscape(rest []byte) (rune, bool) {
	if len(rest) < 6 || rest[0] != '\\' || rest[1] != 'u' {
		return 0, false
	}
	var u rune
	for _, h := range rest[2:6] {
		d, ok := hexDigit(h)
		if !ok {
			return 0, false
		}
		u = u<<4 | d
	}
	return u, true
}

func hexDigit(h byte) (rune, bool) {
	switch {
	case '0' <= h && h <= '9':
		return rune(h - '0'), true
	case 'a' <= h && h <= 'f':
		return rune(h-'a') + 10, true
	case 'A' <= h && h <= 'F':
		return rune(h-'A') + 10, true
	}
	return 0, false
}

func isHigh(u rune) bool { return 0xD800 <= u && u <= 0xDBFF }
func isLow(u rune) bool  { return 0xDC00 <= u && u <= 0xDFFF }

// closeAll returns prefix, then null, then a closer for each opener in open, innermost first.
func closeAll(prefix, open []byte) []byte {
	out := append(append([]byte{}, prefix...), nullText...)
	for i := len(open) - 1; i >= 0; i-- {
		out = append(out, open[i]+2) // '[' + 2 is ']', '{' + 2 is '}'
	}
	return out
}

// value decodes the next value from dec, which reads text json.Valid accepts.
func value(dec *json.Decoder) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch tok {
	case json.Delim('{'):
		object := map[string]any{}
		for dec.More() {
			key, err := dec.Token()
			if err != nil {
				return nil, err
			}
			v, err := value(dec)
			if err != nil {
				return nil, err
			}
			object[key.(string)] = v // a later duplicate replaces an earlier one, as in a dict
		}
		_, err = dec.Token()
		return object, err
	case json.Delim('['):
		var array []any
		for dec.More() {
			v, err := value(dec)
			if err != nil {
				return nil, err
			}
			array = append(array, v)
		}
		_, err = dec.Token()
		return array, err
	}
	return tok, nil
}

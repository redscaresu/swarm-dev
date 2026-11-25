// Package plugin holds the rules over the plugin's own files. Version is bin/swarm.sh's
// plugin_version, rule for rule: the top-level "version" string of a plugin.json. bash-retired
// deletes the bash; until then bash_compare_test.go runs both over every case in testdata/ and
// compares what they print.
package plugin

import "bytes"

// space is the whitespace the scan skips: space, tab, LF and CR, as JSON's.
const space = " \t\n\r"

// scalarEnd is what a bare scalar (true, a number, a bare word) runs up to.
const scalarEnd = `[]"{},:` + space

// versionKey is the top-level key whose value Version returns.
const versionKey = "version"

// asciiEnd is one past the last \u escape Version keeps; one at or past it spoils the string.
const asciiEnd = 128

// hexDigits is the length of a \u escape's code.
const hexDigits = 4

// Version returns the top-level "version" string of the plugin.json text b, and true; or "" and
// false. It is a scanner, not encoding/json, as the bash is: it takes text json.load refuses (no
// commas, bare words) and checks only that brackets pair and escapes are JSON's.
//
// The text stops at its first NUL, as bash's read with an empty -d delimiter does. Leading
// space, tab, LF and CR are skipped, and the text must then open an object. A string runs to its
// closing quote with JSON's escapes; a \u escape is kept only for 1-127, and any other spoils the
// string (bash 3.2's printf has no \u). A string is a key only at depth 1, first in the object or
// after a comma there; the last top-level "version" wins. An object, an array or a bare scalar as
// that value spoils it. It returns false when the object never closes, more than whitespace
// follows it, the top level has no "version", or the last one's value is not a string or is
// spoiled.
func Version(b []byte) (string, bool) {
	if i := bytes.IndexByte(b, 0); i >= 0 {
		b = b[:i]
	}
	rest := bytes.TrimLeft(b, space)
	if len(rest) == 0 || rest[0] != '{' {
		return "", false
	}
	var (
		stack                    []byte // the open objects and arrays, as their { and [
		key, want, found, closed bool   // a key comes next; the version's value comes next; ver counts
		ver                      string
	)
	for len(rest) > 0 && !closed {
		c := rest[0]
		switch {
		case c == '"':
			str, bad, after, ok := readString(rest[1:])
			if !ok {
				return "", false
			}
			rest = after
			if string(stack) == "{" && key {
				key = false
				want = str == versionKey && !bad
			} else if want {
				want, ver, found = false, str, !bad
			}
		case c == '{' || c == '[':
			if want {
				want, found = false, false
			}
			stack = append(stack, c)
			key = string(stack) == "{"
			rest = rest[1:]
		case c == '}' || c == ']':
			if len(stack) == 0 || !pairs(stack[len(stack)-1], c) {
				return "", false
			}
			stack, key, rest = stack[:len(stack)-1], false, rest[1:]
			closed = len(stack) == 0
		case c == ',':
			if string(stack) == "{" {
				key = true
			}
			rest = rest[1:]
		case c == ':' || bytes.IndexByte([]byte(space), c) >= 0:
			rest = rest[1:]
		default:
			if want {
				want, found = false, false
			}
			rest = rest[scalarLen(rest):]
		}
	}
	if !closed || !found || len(bytes.TrimLeft(rest, space)) > 0 {
		return "", false
	}
	return ver, true
}

// pairs reports whether close closes open.
func pairs(open, close byte) bool {
	return open == '{' && close == '}' || open == '[' && close == ']'
}

// scalarLen is the length of the bare scalar rest starts with: up to the first scalarEnd byte.
func scalarLen(rest []byte) int {
	if n := bytes.IndexAny(rest, scalarEnd); n >= 0 {
		return n
	}
	return len(rest)
}

// readString reads a string's body from rest, which follows its opening quote. It returns the
// string, whether a \u escape spoiled it, the text after its closing quote, and false when the
// string never closes or holds an escape JSON does not have.
func readString(rest []byte) (str string, bad bool, after []byte, ok bool) {
	var out []byte
	for {
		n := bytes.IndexAny(rest, `"\`)
		if n < 0 {
			return "", false, nil, false
		}
		out, rest = append(out, rest[:n]...), rest[n:]
		if rest[0] == '"' {
			return string(out), bad, rest[1:], true
		}
		if len(rest) < 2 {
			return "", false, nil, false
		}
		esc := rest[1]
		rest = rest[2:]
		if esc != 'u' {
			ch, known := simpleEscape(esc)
			if !known {
				return "", false, nil, false
			}
			out = append(out, ch)
			continue
		}
		code, hex := hexCode(rest)
		if !hex {
			return "", false, nil, false
		}
		rest = rest[hexDigits:]
		if code > 0 && code < asciiEnd {
			out = append(out, byte(code))
		} else {
			bad = true
		}
	}
}

// simpleEscape is the byte a one-letter JSON escape stands for, and false for a letter that is no
// JSON escape. \u is hexCode's.
func simpleEscape(esc byte) (byte, bool) {
	switch esc {
	case '"', '\\', '/':
		return esc, true
	case 'b':
		return '\b', true
	case 'f':
		return '\f', true
	case 'n':
		return '\n', true
	case 'r':
		return '\r', true
	case 't':
		return '\t', true
	}
	return 0, false
}

// hexCode is the value of the four hex digits rest starts with, and false when it does not start
// with four.
func hexCode(rest []byte) (int, bool) {
	if len(rest) < hexDigits {
		return 0, false
	}
	code := 0
	for _, c := range rest[:hexDigits] {
		var d byte
		switch {
		case c >= '0' && c <= '9':
			d = c - '0'
		case c >= 'a' && c <= 'f':
			d = c - 'a' + 10
		case c >= 'A' && c <= 'F':
			d = c - 'A' + 10
		default:
			return 0, false
		}
		code = code<<4 | int(d)
	}
	return code, true
}

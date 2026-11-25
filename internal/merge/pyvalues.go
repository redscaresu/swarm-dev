// Package merge holds the rules bin/lib/ci_gate.py decides merges by, ported to Go. Nothing runs
// them yet: ci_gate.py still decides, until the story that switches its callers to the binary.
package merge

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// The values this file reads and writes are those ci_gate.py's json.loads gives: nil (None), bool,
// Int, float64, string, []any (a list) and *Object (a dict). Python's isinstance(v, int) is true of
// a bool too, so a caller that mirrors one checks for both. Str, Repr and Dumps also take a Go int
// as an Int, and a []string as a list of strings.
//
// A string the decoder gives holds a lone surrogate (json.loads reads "\ud800" as one) in the three
// bytes UTF-8 would give it. The writers read those bytes back as the surrogate, and any other byte
// that is not UTF-8, b, as U+DC00+b, as Python's surrogateescape reads argv and file names.

// Int is a JSON integer as Python's int holds it, of any size: its decimal digits, with a leading
// minus when it is below zero, and "0" for -0. math/big is not on the standard packages the layer
// checks allow (internal/layers/imports_test.go), and the text keeps every size exactly.
type Int string

// Object is a JSON object as json.loads reads it into a dict: each key once, in the order it first
// appears, with the last value given for it.
type Object struct {
	keys []string
	vals map[string]any
}

// Get returns key's value, and whether o has key.
func (o *Object) Get(key string) (any, bool) {
	v, ok := o.vals[key]
	return v, ok
}

// Set gives key the value v: in key's place when o has it, else as the last key.
func (o *Object) Set(key string, v any) {
	if o.vals == nil {
		o.vals = map[string]any{}
	}
	if _, ok := o.vals[key]; !ok {
		o.keys = append(o.keys, key)
	}
	o.vals[key] = v
}

var (
	// ErrNotJSON is text json.loads refuses with a ValueError, which ci_gate.py catches. The error
	// names the byte offset, not Python's message, which differs between Python versions.
	ErrNotJSON = errors.New("not JSON as python3's json.loads reads it")
	// ErrTooDeep is text that nests lists and objects past maxDepth.
	ErrTooDeep = errors.New("JSON nested too deep")
)

const (
	// maxDepth is how deep lists and objects may nest. Python's own limit is its C stack: python3
	// 3.14 read 100,000 levels and raised RecursionError, which ci_gate.py does not catch, at
	// 1,000,000.
	maxDepth = 100000
	// maxIntDigits is sys.int_info.default_max_str_digits. python3 3.14 refuses an int with more
	// digits, in json.loads too; a python3 from before the limit (CVE-2020-10735) takes any.
	maxIntDigits = 4300
)

// literals are the words json.loads reads as values. "-Infinity" goes before a number is tried.
var literals = []struct {
	text string
	v    any
}{
	{"null", nil}, {"true", true}, {"false", false},
	{"NaN", math.NaN()}, {"Infinity", math.Inf(1)}, {"-Infinity", math.Inf(-1)},
}

var (
	// escapes are the characters json.loads reads after a backslash, other than u, and what each
	// gives.
	escapes = map[byte]byte{'"': '"', '\\': '\\', '/': '/', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t'}
	// pyEscapes are the characters repr writes as a backslash and a letter, beside the quote and
	// the backslash.
	pyEscapes = map[rune]string{'\t': `\t`, '\n': `\n`, '\r': `\r`}
	// jsonEscapes are the characters json.dumps writes as a backslash and one more character.
	jsonEscapes = map[rune]string{'"': `\"`, '\\': `\\`, '\b': `\b`, '\f': `\f`, '\n': `\n`, '\r': `\r`, '\t': `\t`}
)

// Loads returns the value json.loads(text) gives, with whitespace around it.
func Loads(text string) (any, error) {
	v, end, err := RawDecode(text, skipSpace(text, 0))
	if err != nil {
		return nil, err
	}
	if end = skipSpace(text, end); end != len(text) {
		return nil, notJSON(end, "extra data")
	}
	return v, nil
}

// RawDecode returns the value json.JSONDecoder().raw_decode(text, at) gives: the one value that
// starts at byte at, with no whitespace before it, and the offset just past it. Python's text was
// decoded from UTF-8 before raw_decode saw it; RawDecode checks only the bytes it reads.
func RawDecode(text string, at int) (any, int, error) {
	if at < 0 || at > len(text) {
		return nil, at, notJSON(at, "no text at the offset")
	}
	d := &decoder{text: text}
	return d.value(at)
}

// decoder reads text as CPython's C scanner (Modules/_json.c) reads it, with strict on.
type decoder struct {
	text  string
	depth int
}

// notJSON is ErrNotJSON, with what was wrong at byte i.
func notJSON(i int, what string) error {
	return fmt.Errorf("%w: %s at byte %d", ErrNotJSON, what, i)
}

// at returns the byte at i, or 0 past the end, which matches no rule.
func (d *decoder) at(i int) byte {
	if i < len(d.text) {
		return d.text[i]
	}
	return 0
}

// value reads the value at i, and returns it with the offset just past it.
func (d *decoder) value(i int) (any, int, error) {
	switch c := d.at(i); c {
	case '"':
		return d.str(i + 1)
	case '[':
		return d.list(i + 1)
	case '{':
		return d.object(i + 1)
	}
	for _, l := range literals {
		if strings.HasPrefix(d.text[i:], l.text) {
			return l.v, i + len(l.text), nil
		}
	}
	return d.number(i)
}

// number reads an int or a float as the scanner does: a float has a fraction or an exponent, and an
// "e" or "." with no digit after it ends the number before it.
func (d *decoder) number(i int) (any, int, error) {
	j := i
	if d.at(j) == '-' {
		j++
	}
	switch c := d.at(j); {
	case c == '0':
		j++
	case isDigit(c):
		j = d.digits(j)
	default:
		return nil, i, notJSON(i, "expecting value")
	}
	intEnd := j
	if d.at(j) == '.' && isDigit(d.at(j+1)) {
		j = d.digits(j + 1)
	}
	if c := d.at(j); c == 'e' || c == 'E' {
		k := j + 1
		if c := d.at(k); c == '+' || c == '-' {
			k++
		}
		if isDigit(d.at(k)) {
			j = d.digits(k)
		}
	}
	num := d.text[i:j]
	if j > intEnd {
		// num is a JSON number, so ParseFloat's one error is ErrRange, with ±Inf or 0, which
		// Python's float gives too.
		f, _ := strconv.ParseFloat(num, 64)
		return f, j, nil
	}
	if len(strings.TrimPrefix(num, "-")) > maxIntDigits {
		return nil, i, notJSON(i, "an int over "+strconv.Itoa(maxIntDigits)+" digits")
	}
	if num == "-0" {
		num = "0"
	}
	return Int(num), j, nil
}

func (d *decoder) digits(i int) int {
	for isDigit(d.at(i)) {
		i++
	}
	return i
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// str reads the rest of a string whose opening quote ends just before i.
func (d *decoder) str(i int) (string, int, error) {
	var b strings.Builder
	for {
		j := i
		for j < len(d.text) && d.text[j] >= 0x20 && d.text[j] < utf8.RuneSelf && d.text[j] != '"' && d.text[j] != '\\' {
			j++
		}
		b.WriteString(d.text[i:j])
		switch c := d.at(j); {
		case j >= len(d.text):
			return "", j, notJSON(j, "unterminated string")
		case c == '"':
			return b.String(), j + 1, nil
		case c < 0x20:
			return "", j, notJSON(j, "invalid control character")
		case c >= utf8.RuneSelf:
			r, n := utf8.DecodeRuneInString(d.text[j:])
			if r == utf8.RuneError && n == 1 {
				return "", j, notJSON(j, "not UTF-8")
			}
			b.WriteString(d.text[j : j+n])
			i = j + n
		case c == '\\' && d.at(j+1) == 'u':
			r, ok := d.hex4(j + 2)
			if !ok {
				return "", j, notJSON(j, `invalid \uXXXX escape`)
			}
			i = j + 6
			if 0xd800 <= r && r <= 0xdbff && strings.HasPrefix(d.text[i:], `\u`) {
				// A high surrogate takes a low one escaped right after it; else each stays alone.
				if lo, ok := d.hex4(i + 2); ok && 0xdc00 <= lo && lo <= 0xdfff {
					r, i = 0x10000+(r-0xd800)<<10+(lo-0xdc00), i+6
				}
			}
			writeRune(&b, r)
		default:
			e, ok := escapes[d.at(j+1)]
			if !ok {
				return "", j, notJSON(j, "invalid escape")
			}
			b.WriteByte(e)
			i = j + 2
		}
	}
}

// hex4 reads the four hex digits at i. ParseUint with base 16 takes no sign, prefix or "_".
func (d *decoder) hex4(i int) (rune, bool) {
	if i+4 > len(d.text) {
		return 0, false
	}
	v, err := strconv.ParseUint(d.text[i:i+4], 16, 16)
	return rune(v), err == nil
}

// writeRune writes r as UTF-8, and a surrogate, which UTF-8 has no form for, in the three bytes it
// would give one.
func writeRune(b *strings.Builder, r rune) {
	if 0xd800 <= r && r <= 0xdfff {
		b.Write([]byte{0xe0 | byte(r>>12), 0x80 | byte(r>>6)&0x3f, 0x80 | byte(r)&0x3f})
		return
	}
	b.WriteRune(r)
}

func (d *decoder) enter(i int) error {
	if d.depth++; d.depth > maxDepth {
		return fmt.Errorf("%w: past %d levels at byte %d", ErrTooDeep, maxDepth, i)
	}
	return nil
}

// list reads the rest of a list whose "[" ends just before i.
func (d *decoder) list(i int) (any, int, error) {
	if err := d.enter(i); err != nil {
		return nil, i, err
	}
	defer func() { d.depth-- }()
	out := []any{}
	if i = skipSpace(d.text, i); d.at(i) == ']' {
		return out, i + 1, nil
	}
	for {
		v, j, err := d.value(i)
		if err != nil {
			return nil, j, err
		}
		out = append(out, v)
		switch i = skipSpace(d.text, j); d.at(i) {
		case ']':
			return out, i + 1, nil
		case ',':
			i = skipSpace(d.text, i+1)
		default:
			return nil, i, notJSON(i, "expecting ',' delimiter")
		}
	}
}

// object reads the rest of an object whose "{" ends just before i.
func (d *decoder) object(i int) (any, int, error) {
	if err := d.enter(i); err != nil {
		return nil, i, err
	}
	defer func() { d.depth-- }()
	o := &Object{}
	if i = skipSpace(d.text, i); d.at(i) == '}' {
		return o, i + 1, nil
	}
	for {
		if d.at(i) != '"' {
			return nil, i, notJSON(i, "expecting property name enclosed in double quotes")
		}
		k, j, err := d.str(i + 1)
		if err != nil {
			return nil, j, err
		}
		if j = skipSpace(d.text, j); d.at(j) != ':' {
			return nil, j, notJSON(j, "expecting ':' delimiter")
		}
		v, j, err := d.value(skipSpace(d.text, j+1))
		if err != nil {
			return nil, j, err
		}
		o.Set(k, v)
		switch i = skipSpace(d.text, j); d.at(i) {
		case '}':
			return o, i + 1, nil
		case ',':
			i = skipSpace(d.text, i+1)
		default:
			return nil, i, notJSON(i, "expecting ',' delimiter")
		}
	}
}

// skipSpace returns the offset of the first byte from i that is not JSON whitespace.
func skipSpace(text string, i int) int {
	for i < len(text) && strings.IndexByte(" \t\n\r", text[i]) >= 0 {
		i++
	}
	return i
}

// style is how a writer spells the scalars and strings; lists and objects take ", " and ": " in both.
type style struct {
	none, yes, no string
	str           func(*strings.Builder, string)
	float         func(float64) string
}

var (
	pyStyle   = style{"None", "True", "False", writePyStr, floatRepr}
	jsonStyle = style{"null", "true", "false", writeJSONStr, jsonFloat}
)

// Str returns v as Python's str(v) and "%s" % v give it.
func Str(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return Repr(v)
}

// Repr returns v as Python's repr(v) and "%r" % v give it.
func Repr(v any) string {
	var b strings.Builder
	write(&b, v, &pyStyle)
	return b.String()
}

// Dumps returns json.dumps(v) with its defaults: ", " and ": " between items, every character past
// "~" as a \u escape (a pair of them past U+FFFF), NaN and Infinity as Python writes them, and no
// HTML escaping. The text is all ASCII, so it is the bytes json.dumps(v).encode("utf-8") gives.
func Dumps(v any) string {
	var b strings.Builder
	write(&b, v, &jsonStyle)
	return b.String()
}

func write(b *strings.Builder, v any, st *style) {
	switch v := v.(type) {
	case nil:
		b.WriteString(st.none)
	case bool:
		if v {
			b.WriteString(st.yes)
		} else {
			b.WriteString(st.no)
		}
	case Int:
		b.WriteString(string(v))
	case int:
		b.WriteString(strconv.Itoa(v))
	case float64:
		b.WriteString(st.float(v))
	case string:
		st.str(b, v)
	case []string:
		writeItems(b, '[', ']', len(v), func(i int) { st.str(b, v[i]) })
	case []any:
		writeItems(b, '[', ']', len(v), func(i int) { write(b, v[i], st) })
	case *Object:
		writeItems(b, '{', '}', len(v.keys), func(i int) {
			st.str(b, v.keys[i])
			b.WriteString(": ")
			write(b, v.vals[v.keys[i]], st)
		})
	default:
		panic(fmt.Sprintf("merge: %T is not a value json.loads gives", v))
	}
}

func writeItems(b *strings.Builder, open, end byte, n int, item func(int)) {
	b.WriteByte(open)
	for i := range n {
		if i > 0 {
			b.WriteString(", ")
		}
		item(i)
	}
	b.WriteByte(end)
}

// pyRune reads the code point at the start of s as the package comment says Python holds it.
func pyRune(s string) (rune, int) {
	r, n := utf8.DecodeRuneInString(s)
	switch {
	case r != utf8.RuneError || n != 1:
		return r, n
	case len(s) >= 3 && s[0] == 0xed && s[1]&0xe0 == 0xa0 && s[2]&0xc0 == 0x80:
		return rune(s[0]&0x0f)<<12 | rune(s[1]&0x3f)<<6 | rune(s[2]&0x3f), 3
	}
	return 0xdc00 + rune(s[0]), 1
}

// writePyStr writes s as Python's repr does: in single quotes, or double ones when s holds a single
// quote and no double one; a character Python's isprintable refuses as \x, \u or \U and its hex.
// Go's unicode tables stand in for Python's, which may not have the newest characters.
func writePyStr(b *strings.Builder, s string) {
	quote := '\''
	if strings.ContainsRune(s, '\'') && !strings.ContainsRune(s, '"') {
		quote = '"'
	}
	b.WriteRune(quote)
	for i := 0; i < len(s); {
		r, n := pyRune(s[i:])
		switch {
		case r == quote || r == '\\':
			b.WriteRune('\\')
			b.WriteRune(r)
		case pyEscapes[r] != "":
			b.WriteString(pyEscapes[r])
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(b, `\x%02x`, r)
		case r < 0x7f || unicode.IsPrint(r):
			b.WriteString(s[i : i+n])
		case r <= 0xff:
			fmt.Fprintf(b, `\x%02x`, r)
		case r <= 0xffff:
			fmt.Fprintf(b, `\u%04x`, r)
		default:
			fmt.Fprintf(b, `\U%08x`, r)
		}
		i += n
	}
	b.WriteRune(quote)
}

// writeJSONStr writes s as json.dumps does with ensure_ascii on.
func writeJSONStr(b *strings.Builder, s string) {
	b.WriteByte('"')
	for i := 0; i < len(s); {
		r, n := pyRune(s[i:])
		switch {
		case jsonEscapes[r] != "":
			b.WriteString(jsonEscapes[r])
		case 0x20 <= r && r <= '~':
			b.WriteRune(r)
		case r > 0xffff:
			fmt.Fprintf(b, `\u%04x\u%04x`, 0xd800+(r-0x10000)>>10, 0xdc00+(r-0x10000)&0x3ff)
		default:
			fmt.Fprintf(b, `\u%04x`, r)
		}
		i += n
	}
	b.WriteByte('"')
}

// floatRepr returns f as Python's repr does: the shortest digits that read back as f, with an
// exponent when the point would sit more than 16 places right of the first digit or 4 or more left
// of it, else with ".0" when f is whole.
func floatRepr(f float64) string {
	switch {
	case math.IsNaN(f):
		return "nan"
	case math.IsInf(f, 1):
		return "inf"
	case math.IsInf(f, -1):
		return "-inf"
	}
	sign, e := "", strconv.FormatFloat(f, 'e', -1, 64) // -d.ddde±XX
	if e[0] == '-' {
		sign, e = "-", e[1:]
	}
	mant, exp, _ := strings.Cut(e, "e")
	digits := strings.Replace(mant, ".", "", 1)
	x, _ := strconv.Atoi(exp)
	switch point := x + 1; {
	case point <= -4 || point > 16:
		return sign + mant + "e" + fmt.Sprintf("%+03d", x)
	case point <= 0:
		return sign + "0." + strings.Repeat("0", -point) + digits
	case point >= len(digits):
		return sign + digits + strings.Repeat("0", point-len(digits)) + ".0"
	default:
		return sign + digits[:point] + "." + digits[point:]
	}
}

// jsonFloat returns f as json.dumps does: NaN and ±Infinity as words, else as repr.
func jsonFloat(f float64) string {
	switch {
	case math.IsNaN(f):
		return "NaN"
	case math.IsInf(f, 1):
		return "Infinity"
	case math.IsInf(f, -1):
		return "-Infinity"
	}
	return floatRepr(f)
}

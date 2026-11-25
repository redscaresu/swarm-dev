// Package pyjson writes JSON as Python's json.dump writes it with its default arguments, and reads
// it as json.loads reads a str. Old sessions wrote .swarm/gh-cache with json.dump, and the
// differential run compares the bytes each side writes, so the Go must write the same bytes.
//
// A decoded value is nil, bool, string, int64, BigInt (an int past int64), float64, []any or
// Object. Encode takes the same types, and int. A string holds UTF-8, except that a lone surrogate,
// which a Python str can hold, is held as its three-byte form (WTF-8), so it reads and writes back
// as Python's does.
package pyjson

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"
)

// maxDepth is how deep arrays and objects may nest. Python raises RecursionError, which no caller
// catches, somewhere past its recursion limit; Decode and Encode stop here instead of growing
// without bound, and so Encode refuses a list that holds itself, where json.dump raises ValueError.
const maxDepth = 10000

// maxIntDigits is the most digits an int may have: Python 3.11 and later raise ValueError past it,
// reading or writing one (sys.get_int_max_str_digits), and Decode and Encode refuse it too.
// Python 3.10 and older had no limit.
const maxIntDigits = 4300

// wholeFloatLimit is where Python's repr of a whole float turns to an exponent: 1e16 is "1e+16".
const wholeFloatLimit = 1e16

var (
	// ErrNotJSON is text that json.loads raises ValueError on.
	ErrNotJSON = errors.New("pyjson: not JSON as json.loads reads it")
	// ErrTooDeep is text nested past maxDepth.
	ErrTooDeep = errors.New("pyjson: nested deeper than maxDepth")
	// ErrCannotEncode is a value Encode refuses: a type json.dump has no form for, a BigInt that is
	// not an int's digits, a float that is not a whole number (no cache record holds one), an int past maxIntDigits, a
	// string that no Python str holds, an Object with a repeated key, which no Python dict holds,
	// or nesting past maxDepth.
	ErrCannotEncode = errors.New("pyjson: cannot encode")
)

// BigInt is an int past int64, as its decimal digits with a leading - when it is negative.
type BigInt string

// valid reports whether n is an int as Python writes one: no leading zero, plus sign or space,
// and no -0, since a Python int has no negative zero.
func (n BigInt) valid() bool {
	digits := strings.TrimPrefix(string(n), "-")
	if digits == "" || digits[0] == '0' && n != "0" {
		return false
	}
	for i := 0; i < len(digits); i++ {
		if !isDigit(digits[i]) {
			return false
		}
	}
	return true
}

// Member is one key and its value in an Object.
type Member struct {
	Key   string
	Value any
}

// Object is a JSON object with its keys in order, as a Python dict keeps them: a repeated key
// decodes to the place of its first and the value of its last.
type Object []Member

// Get returns key's value and whether the object has it.
func (o Object) Get(key string) (any, bool) {
	for _, m := range o {
		if m.Key == key {
			return m.Value, true
		}
	}
	return nil, false
}

// Encode returns v as json.dump(v, f) writes it: ", " and ": " separators, every character
// outside space to "~" escaped (Python's short forms, else \u with lower-case hex, and a surrogate
// pair above U+FFFF), an Object's keys in its own order, and an int as its digits.
func Encode(v any) ([]byte, error) {
	return encode(nil, v, 0)
}

func encode(b []byte, v any, depth int) ([]byte, error) {
	switch v := v.(type) {
	case nil:
		return append(b, "null"...), nil
	case bool:
		return strconv.AppendBool(b, v), nil
	case int:
		return strconv.AppendInt(b, int64(v), 10), nil
	case int64:
		return strconv.AppendInt(b, v, 10), nil
	case BigInt:
		if !v.valid() {
			return nil, fmt.Errorf("%w: the BigInt %q, which is not an int's digits", ErrCannotEncode, string(v))
		}
		if len(strings.TrimPrefix(string(v), "-")) > maxIntDigits {
			return nil, fmt.Errorf("%w: an int of more than %d digits", ErrCannotEncode, maxIntDigits)
		}
		return append(b, v...), nil
	case float64:
		return encodeFloat(b, v)
	case string:
		return encodeString(b, v)
	case []any, Object:
		if depth == maxDepth {
			return nil, fmt.Errorf("%w: nesting past %d", ErrCannotEncode, maxDepth)
		}
		return encodeContainer(b, v, depth+1)
	}
	return nil, fmt.Errorf("%w: a %T", ErrCannotEncode, v)
}

func encodeContainer(b []byte, v any, depth int) ([]byte, error) {
	if o, ok := v.(Object); ok {
		return encodeObject(b, o, depth)
	}
	b = append(b, '[')
	for i, x := range v.([]any) {
		if i > 0 {
			b = append(b, ", "...)
		}
		var err error
		if b, err = encode(b, x, depth); err != nil {
			return nil, err
		}
	}
	return append(b, ']'), nil
}

func encodeObject(b []byte, o Object, depth int) ([]byte, error) {
	seen := make(map[string]bool, len(o))
	b = append(b, '{')
	for i, m := range o {
		if seen[m.Key] {
			return nil, fmt.Errorf("%w: the key %q twice", ErrCannotEncode, m.Key)
		}
		seen[m.Key] = true
		if i > 0 {
			b = append(b, ", "...)
		}
		var err error
		if b, err = encodeString(b, m.Key); err != nil {
			return nil, err
		}
		b = append(b, ": "...)
		if b, err = encode(b, m.Value, depth); err != nil {
			return nil, err
		}
	}
	return append(b, '}'), nil
}

// encodeFloat writes a whole float as Python's repr does: "1.0", "-0.0", "1e+16".
func encodeFloat(b []byte, f float64) ([]byte, error) {
	if math.IsNaN(f) || math.IsInf(f, 0) || f != math.Trunc(f) {
		return nil, fmt.Errorf("%w: the float %v, which is not a whole number", ErrCannotEncode, f)
	}
	if math.Abs(f) >= wholeFloatLimit {
		return strconv.AppendFloat(b, f, 'e', -1, 64), nil
	}
	return append(strconv.AppendFloat(b, f, 'f', -1, 64), ".0"...), nil
}

// shortEscapes are the escapes json.dump writes in place of \u.
var shortEscapes = map[rune]string{
	'"': `\"`, '\\': `\\`, '\b': `\b`, '\f': `\f`, '\n': `\n`, '\r': `\r`, '\t': `\t`,
}

const hexDigits = "0123456789abcdef"

func appendU(b []byte, u rune) []byte {
	return append(b, '\\', 'u', hexDigits[u>>12&0xf], hexDigits[u>>8&0xf], hexDigits[u>>4&0xf], hexDigits[u&0xf])
}

func encodeString(b []byte, s string) ([]byte, error) {
	b = append(b, '"')
	for i := 0; i < len(s); {
		r, size := nextRune(s[i:])
		if size == 0 {
			return nil, fmt.Errorf("%w: a string that is not UTF-8 at byte %d", ErrCannotEncode, i)
		}
		i += size
		switch esc, short := shortEscapes[r]; {
		case short:
			b = append(b, esc...)
		case r >= ' ' && r <= '~':
			b = append(b, byte(r))
		case r > 0xffff:
			r -= 0x10000
			b = appendU(appendU(b, 0xd800|r>>10), 0xdc00|r&0x3ff)
		default:
			b = appendU(b, r)
		}
	}
	return append(b, '"'), nil
}

// nextRune decodes the first character of s, a lone surrogate's three-byte form among them. Its
// size is 0 when s does not start with one.
func nextRune(s string) (rune, int) {
	r, size := utf8.DecodeRuneInString(s)
	if r != utf8.RuneError || size > 1 {
		return r, size
	}
	if len(s) >= 3 && s[0] == 0xed && s[1] >= 0xa0 && s[1] <= 0xbf && s[2] >= 0x80 && s[2] <= 0xbf {
		return 0xd000 | rune(s[1]&0x3f)<<6 | rune(s[2]&0x3f), 3
	}
	return 0, 0
}

// appendSurrogate writes a lone surrogate in its three-byte form, which utf8.AppendRune refuses.
func appendSurrogate(b []byte, u rune) []byte {
	return append(b, 0xed, byte(0x80|u>>6&0x3f), byte(0x80|u&0x3f))
}

// Decode returns the value in data as json.loads(data.decode("utf-8")) reads it: an Object keeps
// its keys in order, a repeated key's last value wins, an int stays an int, and NaN, Infinity and
// -Infinity read as floats. Like json.loads it refuses text that is not UTF-8, a leading byte
// order mark, a raw control character in a string and anything but whitespace after the value.
// json.loads of bytes, which also takes UTF-16 and a UTF-8 BOM, is not what it reads.
func Decode(data []byte) (any, error) {
	if !utf8.Valid(data) {
		return nil, fmt.Errorf("%w: not UTF-8", ErrNotJSON)
	}
	d := &decoder{data: data}
	d.space()
	v, err := d.value(0)
	if err != nil {
		return nil, err
	}
	if d.space(); d.pos < len(d.data) {
		return nil, d.fail("data after the value")
	}
	return v, nil
}

type decoder struct {
	data []byte
	pos  int
}

func (d *decoder) fail(what string) error {
	return fmt.Errorf("%w: %s at byte %d", ErrNotJSON, what, d.pos)
}

// space skips the whitespace json.loads skips, which is these four and no other.
func (d *decoder) space() {
	for d.pos < len(d.data) && (d.data[d.pos] == ' ' || d.data[d.pos] == '\t' || d.data[d.pos] == '\n' || d.data[d.pos] == '\r') {
		d.pos++
	}
}

// literal consumes word when the text has it next.
func (d *decoder) literal(word string) bool {
	if len(d.data)-d.pos >= len(word) && string(d.data[d.pos:d.pos+len(word)]) == word {
		d.pos += len(word)
		return true
	}
	return false
}

// literals are the words json.loads reads, each with its value.
var literals = []Member{
	{"null", nil}, {"true", true}, {"false", false},
	{"NaN", math.NaN()}, {"Infinity", math.Inf(1)}, {"-Infinity", math.Inf(-1)},
}

func (d *decoder) value(depth int) (any, error) {
	if d.pos == len(d.data) {
		return nil, d.fail("no value")
	}
	switch d.data[d.pos] {
	case '"':
		d.pos++
		return d.str()
	case '[', '{':
		if depth == maxDepth {
			return nil, fmt.Errorf("%w at byte %d", ErrTooDeep, d.pos)
		}
		if d.data[d.pos] == '[' {
			return d.array(depth + 1)
		}
		return d.object(depth + 1)
	}
	for _, l := range literals {
		if d.literal(l.Key) {
			return l.Value, nil
		}
	}
	return d.number()
}

func (d *decoder) array(depth int) (any, error) {
	d.pos++
	list := []any{}
	if d.space(); d.literal("]") {
		return list, nil
	}
	for {
		v, err := d.value(depth)
		if err != nil {
			return nil, err
		}
		list = append(list, v)
		if d.space(); d.literal("]") {
			return list, nil
		}
		if !d.literal(",") {
			return nil, d.fail("no , or ] after an item")
		}
		d.space()
	}
}

func (d *decoder) object(depth int) (any, error) {
	d.pos++
	obj, at := Object{}, map[string]int{}
	if d.space(); d.literal("}") {
		return obj, nil
	}
	for {
		if !d.literal(`"`) {
			return nil, d.fail("a key that is not a string")
		}
		key, err := d.str()
		if err != nil {
			return nil, err
		}
		if d.space(); !d.literal(":") {
			return nil, d.fail("no : after a key")
		}
		d.space()
		v, err := d.value(depth)
		if err != nil {
			return nil, err
		}
		if i, seen := at[key]; seen {
			obj[i].Value = v
		} else {
			at[key] = len(obj)
			obj = append(obj, Member{key, v})
		}
		if d.space(); d.literal("}") {
			return obj, nil
		}
		if !d.literal(",") {
			return nil, d.fail("no , or } after a member")
		}
		d.space()
	}
}

// unescapes are the one-character escapes json.loads reads.
var unescapes = map[byte]byte{'"': '"', '\\': '\\', '/': '/', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t'}

// str reads a string's body, the opening quote already consumed.
func (d *decoder) str() (string, error) {
	var b []byte
	for {
		if d.pos == len(d.data) {
			return "", d.fail("an unterminated string")
		}
		c := d.data[d.pos]
		d.pos++
		switch {
		case c == '"':
			return string(b), nil
		case c < ' ':
			d.pos--
			return "", d.fail("a control character in a string")
		case c != '\\':
			b = append(b, c)
		case d.pos == len(d.data):
			return "", d.fail("an unterminated string")
		case d.data[d.pos] == 'u':
			var err error
			if b, err = d.unicode(b); err != nil {
				return "", err
			}
		default:
			u, ok := unescapes[d.data[d.pos]]
			if !ok {
				return "", d.fail("an invalid escape")
			}
			b = append(b, u)
			d.pos++
		}
	}
}

// unicode reads a \u escape at the u, joining a high surrogate to a low one escaped right after
// it, as json.loads does; a surrogate left on its own is kept.
func (d *decoder) unicode(b []byte) ([]byte, error) {
	u, ok := d.hex4(d.pos + 1)
	if !ok {
		return nil, d.fail(`an invalid \u escape`)
	}
	d.pos += 5
	if u >= 0xd800 && u <= 0xdbff && d.pos+1 < len(d.data) && d.data[d.pos] == '\\' && d.data[d.pos+1] == 'u' {
		if low, ok := d.hex4(d.pos + 2); ok && low >= 0xdc00 && low <= 0xdfff {
			d.pos += 6
			return utf8.AppendRune(b, 0x10000+(u-0xd800)<<10|(low-0xdc00)), nil
		}
	}
	if u >= 0xd800 && u <= 0xdfff {
		return appendSurrogate(b, u), nil
	}
	return utf8.AppendRune(b, u), nil
}

// hex4 reads the four hex digits at i.
func (d *decoder) hex4(i int) (rune, bool) {
	if i+4 > len(d.data) {
		return 0, false
	}
	u, err := strconv.ParseUint(string(d.data[i:i+4]), 16, 32)
	return rune(u), err == nil // ParseUint takes no sign, prefix or _ in base 16
}

// hasSign is an exponent's sign.
func hasSign(c byte) bool { return c == '+' || c == '-' }

// number reads -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?, an int when it has neither part.
func (d *decoder) number() (any, error) {
	start := d.pos
	d.literal("-")
	switch {
	case d.literal("0"): // a 0 starts no longer int: "01" is 0 with data after it
	case d.pos < len(d.data) && d.data[d.pos] >= '1' && d.data[d.pos] <= '9':
		d.digits()
	default:
		return nil, d.fail("no value")
	}
	isFloat := false
	if d.pos+1 < len(d.data) && d.data[d.pos] == '.' && isDigit(d.data[d.pos+1]) {
		d.pos++
		d.digits()
		isFloat = true
	}
	if d.pos < len(d.data) && (d.data[d.pos] == 'e' || d.data[d.pos] == 'E') {
		mark := d.pos
		d.pos++
		if d.pos < len(d.data) && hasSign(d.data[d.pos]) {
			d.pos++
		}
		if d.digits() {
			isFloat = true
		} else {
			d.pos = mark
		}
	}
	text := string(d.data[start:d.pos])
	if isFloat {
		f, err := strconv.ParseFloat(text, 64)
		if err != nil && !errors.Is(err, strconv.ErrRange) {
			return nil, d.fail("a bad number")
		}
		return f, nil // past the range, Python's float() gives inf or 0 as ParseFloat does
	}
	if n, err := strconv.ParseInt(text, 10, 64); err == nil {
		return n, nil
	}
	if len(strings.TrimPrefix(text, "-")) > maxIntDigits {
		return nil, d.fail(fmt.Sprintf("an int of more than %d digits", maxIntDigits))
	}
	return BigInt(text), nil
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// digits consumes a run of ASCII digits, the only digits json.loads reads, and says if it had one.
func (d *decoder) digits() bool {
	start := d.pos
	for d.pos < len(d.data) && isDigit(d.data[d.pos]) {
		d.pos++
	}
	return d.pos > start
}

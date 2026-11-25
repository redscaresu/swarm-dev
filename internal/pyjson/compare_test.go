package pyjson

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

// pythonSeconds bounds each python3 run.
const pythonSeconds = 60

// encodeScript prints, for each value in cases (a list the test writes in its place), json.dump's
// bytes in hex, after checking json.dumps writes the same.
const encodeScript = `import io, json, sys
cases = [
%s]
for v in cases:
    f = io.StringIO()
    json.dump(v, f)
    if f.getvalue() != json.dumps(v):
        sys.exit("json.dump and json.dumps differ on %%r" %% (v,))
    print(f.getvalue().encode("ascii").hex())
`

// decodeScript reads hex texts, one a line, and prints what json.loads makes of each in canon's
// form, or "error" where it raises ValueError.
const decodeScript = `import json, math, struct, sys
def canon(v):
    if v is None: return "N"
    if v is True: return "T"
    if v is False: return "F"
    if isinstance(v, int): return "i%d" % v
    if isinstance(v, float): return "fnan" if math.isnan(v) else "f" + struct.pack(">d", v).hex()
    if isinstance(v, str): return "s" + v.encode("utf-8", "surrogatepass").hex()
    if isinstance(v, list): return "[" + ",".join(canon(x) for x in v) + "]"
    return "{" + ",".join(canon(k) + ":" + canon(x) for k, x in v.items()) + "}"
for line in sys.stdin:
    try:
        print(canon(json.loads(bytes.fromhex(line.strip()).decode("utf-8"))))
    except ValueError:
        print("error")
`

// python runs script under python3 -I with stdin and returns its output lines.
func python(t *testing.T, script, stdin string) []string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), pythonSeconds*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-c", script)
	cmd.Stdin = strings.NewReader(stdin)
	out, err := cmd.Output()
	if err != nil {
		var stderr []byte
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			stderr = exit.Stderr
		}
		t.Fatalf("python3: %v\n%s", err, stderr)
	}
	return strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
}

// pyLiteral writes v as Python source for the same value. A string goes as its bytes, decoded
// with surrogatepass, so a lone surrogate's three-byte form is the same lone surrogate in Python.
func pyLiteral(v any) string {
	switch v := v.(type) {
	case nil:
		return "None"
	case bool:
		if v {
			return "True"
		}
		return "False"
	case int:
		return strconv.Itoa(v)
	case int64:
		return strconv.FormatInt(v, 10)
	case BigInt:
		return string(v)
	case float64:
		return "float.fromhex('" + strconv.FormatFloat(v, 'x', -1, 64) + "')"
	case string:
		return "bytes.fromhex('" + hex.EncodeToString([]byte(v)) + "').decode('utf-8', 'surrogatepass')"
	case []any:
		parts := make([]string, len(v))
		for i, x := range v {
			parts[i] = pyLiteral(x)
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case Object:
		parts := make([]string, len(v))
		for i, m := range v {
			parts[i] = "(" + pyLiteral(m.Key) + ", " + pyLiteral(m.Value) + ")"
		}
		return "dict([" + strings.Join(parts, ", ") + "])"
	}
	panic(fmt.Sprintf("pyLiteral: a %T", v))
}

// canon writes a decoded value in decodeScript's canon form.
func canon(v any) string {
	switch v := v.(type) {
	case nil:
		return "N"
	case bool:
		if v {
			return "T"
		}
		return "F"
	case int64:
		return "i" + strconv.FormatInt(v, 10)
	case BigInt:
		return "i" + string(v)
	case float64:
		if math.IsNaN(v) {
			return "fnan"
		}
		return fmt.Sprintf("f%016x", math.Float64bits(v))
	case string:
		return "s" + hex.EncodeToString([]byte(v))
	case []any:
		parts := make([]string, len(v))
		for i, x := range v {
			parts[i] = canon(x)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case Object:
		parts := make([]string, len(v))
		for i, m := range v {
			parts[i] = canon(m.Key) + ":" + canon(m.Value)
		}
		return "{" + strings.Join(parts, ",") + "}"
	}
	return fmt.Sprintf("a %T", v)
}

// controls is every control character, then DEL, which json.dump escapes too.
func controls() string {
	var b strings.Builder
	for c := 0; c < 0x20; c++ {
		b.WriteByte(byte(c))
	}
	return b.String() + "\x7f"
}

// encodeCases are the values json.dump and Encode both write.
var encodeCases = []any{
	nil, true, false,
	0, -1, int64(math.MaxInt64), int64(math.MinInt64), BigInt("1267650600228229401496703205376"), BigInt("-9223372036854775809"),
	0.0, math.Copysign(0, -1), 1.0, -3.0, 1e15, 9999999999999998.0, 1e16, -1.5e17, 1e100, math.MaxFloat64,
	"", controls(), `quote " backslash \ slash / tilde ~ space`,
	"caf\u00e9 \u65e5\u672c \u2028 \ufffd \uffff", "\U0001f600 \U0010ffff",
	"\xed\xa0\x80", "\xed\xbf\xbf", "a\xed\xa0\x80\xed\xb0\x80b", // lone surrogates, and a pair held as two
	[]any{}, Object{}, []any{[]any{}, Object{}},
	Object{{"z", 1}, {"a", Object{{"y", []any{2, "x"}}, {"b", nil}}}, {"m", Object{}}},
	Object{{"k\u00e9\n\"", "\u00e9"}, {"\U0001f600", []any{true, false}}},
}

// decodeCases are the texts json.loads and Decode both read, or both refuse.
var decodeCases = []string{
	// Values and empty containers, with every whitespace json.loads skips.
	`null`, `true`, `false`, `[]`, `{}`, `""`, " \t\n\r[ ]\r\n", `{ }`, `[[], {}, [{}]]`,
	// Key order, kept; a repeated key, its last value in its first place.
	`{"b": 1, "a": 2, "c": {"z": [], "y": {}}}`, `{"a": 1, "a": 2}`, `{"a": 1, "b": 2, "a": {"x": 3}}`,
	// Numbers: ints stay ints, past int64 too; floats past the range read as Python's float() does.
	`0`, `-0`, `-0.0`, `1.0`, `1.5`, `1e5`, `1E+5`, `1e-5`, `-12.5e-3`, `9223372036854775807`,
	`9223372036854775808`, `-9223372036854775809`, `123456789012345678901234567890`, `1e400`, `-1e400`, `1e-400`,
	`01`, `1.`, `.5`, `-`, `+1`, `1e`, `1e+`, `0x10`, `1_000`, `[1.]`, `[-]`,
	// NaN and the infinities, which json.loads takes; their spellings it does not.
	`NaN`, `Infinity`, `-Infinity`, `[NaN, -Infinity, Infinity]`, `-NaN`, `nan`, `infinity`, `+Infinity`,
	// Strings: every escape, \u in either case, surrogate pairs and lone surrogates, raw non-ASCII.
	`"\"\\\/\b\f\n\r\t"`, `"\u0000\u001f\u007f\u00e9\u00E9\u2028\uffff"`, "\"caf\u00e9 \u65e5\u672c \U0001f600\"", "\"\x7f\"",
	`"\ud83d\ude00"`, `"\uD83D\uDE00"`, `"\ud800"`, `"\udc00"`, `"\ud800x"`, `"\udc00\ud800"`, `"\ud800\u0041"`,
	`"\ud800\ud800\udc00"`, `"\ud800\uzzzz"`, `"\ud83d\ude00\ude00"`, `{"\ud800": "\udfff"}`,
	// Strings json.loads refuses: bad escapes, a raw control character, no closing quote.
	`"\x"`, `"\u12"`, `"\u12g4"`, `"\u+123"`, `"\u-123"`, `"\U0041"`, `"\'"`, "\"a\tb\"", "\"a\nb\"", "\"\x00\"", `"abc`, `"abc\`,
	// Data after the value, trailing commas and other broken containers.
	`{} x`, `[] []`, `1 2`, `{"a": 1}}`, `[1,]`, `{"a": 1,}`, `{,}`, `[,1]`, `[1 2]`, `{"a" 1}`, `{"a": }`,
	`{1: 2}`, `{'a': 1}`, `[`, `{"a": 1`, `]`,
	// Text that is no value: empty, whitespace json.loads does not skip, a BOM, not UTF-8.
	``, `   `, "\f1", "\u00a01", "\ufeff{}", "\"\xff\"", "\"\xed\xa0\x80\"", `True`, `nul`, `nulll`,
}

func TestEncodeMatchesPython(t *testing.T) {
	lits := make([]string, len(encodeCases))
	for i, v := range encodeCases {
		lits[i] = "    " + pyLiteral(v) + ",\n"
	}
	want := python(t, fmt.Sprintf(encodeScript, strings.Join(lits, "")), "")
	if len(want) != len(encodeCases) {
		t.Fatalf("python3 printed %d lines for %d cases", len(want), len(encodeCases))
	}
	for i, v := range encodeCases {
		got, err := Encode(v)
		if err != nil {
			t.Errorf("Encode(%s): %v", pyLiteral(v), err)
			continue
		}
		if wantText, _ := hex.DecodeString(want[i]); string(got) != string(wantText) {
			t.Errorf("Encode(%s)\n got %s\nwant %s", pyLiteral(v), got, wantText)
		}
	}
}

func TestDecodeMatchesPython(t *testing.T) {
	var in strings.Builder
	for _, text := range decodeCases {
		in.WriteString(hex.EncodeToString([]byte(text)) + "\n")
	}
	want := python(t, decodeScript, in.String())
	if len(want) != len(decodeCases) {
		t.Fatalf("python3 printed %d lines for %d cases", len(want), len(decodeCases))
	}
	for i, text := range decodeCases {
		got := "error"
		if v, err := Decode([]byte(text)); err == nil {
			got = canon(v)
		} else if !errors.Is(err, ErrNotJSON) {
			t.Errorf("Decode(%q): %v, not ErrNotJSON", text, err)
		}
		if got != want[i] {
			t.Errorf("Decode(%q)\n got %s\nwant %s", text, got, want[i])
		}
	}
}

// nested is n arrays, one inside the next, around an empty one.
func nested(n int) any {
	var v any = []any{}
	for i := 0; i < n; i++ {
		v = []any{v}
	}
	return v
}

// digits is an int of n digits.
func digits(n int) BigInt { return BigInt(strings.Repeat("9", n)) }

// TestEncodeRefuses checks the values Encode refuses where json.dump writes them (a float that is
// not whole, NaN and the infinities) or raises (a list that holds itself, an int past the digit
// limit), or where no Python value is the same (bytes that are not UTF-8, a repeated key, a BigInt
// that is not an int's digits, a type json.dump has no form for). It checks the depth and digit limits' edges too.
func TestEncodeRefuses(t *testing.T) {
	cycle := make([]any, 1)
	cycle[0] = cycle
	refused := []any{
		1.5, -0.25, 1e-300, math.NaN(), math.Inf(1), math.Inf(-1),
		"\xff", "a\xed\xa0", []any{"\xc3"}, Object{{"a", 1}, {"a", 2}}, Object{{"\xff", 1}},
		map[string]any{"a": 1}, []string{"a"}, uint(1), float32(1), []any{struct{}{}},
		BigInt(""), BigInt("-"), BigInt("-0"), BigInt("01"), BigInt("-01"), BigInt("+1"), BigInt("1.5"), BigInt(" 1"), []any{BigInt("1e5")},
		cycle, nested(maxDepth), digits(maxIntDigits + 1), "-" + digits(maxIntDigits+1),
	}
	for i, v := range refused {
		if _, err := Encode(v); !errors.Is(err, ErrCannotEncode) {
			t.Errorf("Encode of refused case %d, a %T: %v; want ErrCannotEncode", i, v, err)
		}
	}
	for i, v := range []any{nested(maxDepth - 1), digits(maxIntDigits), "-" + digits(maxIntDigits), BigInt("0")} {
		if _, err := Encode(v); err != nil {
			t.Errorf("Encode of edge case %d: %v", i, err)
		}
	}
}

// TestIntDigitLimitMatchesPython reads and writes ints at the digit limit's edge through Python
// 3.11 or later, which has the limit, and Decode and Encode. An older Python has none to compare.
func TestIntDigitLimitMatchesPython(t *testing.T) {
	if python(t, "import sys; print(hasattr(sys, 'get_int_max_str_digits'))", "")[0] != "True" {
		t.Skip("python3 is older than 3.11, which has no int digit limit")
	}
	ok, over := strings.Repeat("9", maxIntDigits), strings.Repeat("9", maxIntDigits+1)
	texts := []string{ok, "-" + ok, over, "-" + over, "[" + over + "]"}
	var in strings.Builder
	for _, text := range texts {
		in.WriteString(hex.EncodeToString([]byte(text)) + "\n")
	}
	want := python(t, decodeScript, in.String())
	for i, text := range texts {
		got := "error"
		if v, err := Decode([]byte(text)); err == nil {
			got = canon(v)
		}
		if got != want[i] {
			t.Errorf("Decode of case %d (%d bytes)\n got %.40s\nwant %.40s", i, len(text), got, want[i])
		}
	}
	wrote := python(t, "import json\nfor n in (4300, 4301):\n    try:\n        json.dumps(int('9' * n)); print('ok')\n    except ValueError:\n        print('error')\n", "")
	for i, n := range []int{maxIntDigits, maxIntDigits + 1} {
		got := "ok"
		if _, err := Encode(digits(n)); err != nil {
			got = "error"
		}
		if got != wrote[i] {
			t.Errorf("Encode of a %d-digit int: %s, json.dumps: %s", n, got, wrote[i])
		}
	}
}

func TestDecodeTooDeep(t *testing.T) {
	deep := strings.Repeat("[", maxDepth+1) + strings.Repeat("]", maxDepth+1)
	if _, err := Decode([]byte(deep)); !errors.Is(err, ErrTooDeep) {
		t.Errorf("Decode of %d nested arrays: %v; want ErrTooDeep", maxDepth+1, err)
	}
	ok := strings.Repeat(`{"a": `, maxDepth) + "1" + strings.Repeat("}", maxDepth)
	if _, err := Decode([]byte(ok)); err != nil {
		t.Errorf("Decode of %d nested objects: %v", maxDepth, err)
	}
}

func TestObjectGet(t *testing.T) {
	v, err := Decode([]byte(`{"a": 1, "b": null, "a": 2}`))
	if err != nil {
		t.Fatal(err)
	}
	o := v.(Object)
	if got, ok := o.Get("a"); !ok || got != int64(2) {
		t.Errorf(`Get("a") = %v, %v; want 2, true`, got, ok)
	}
	if got, ok := o.Get("b"); !ok || got != nil {
		t.Errorf(`Get("b") = %v, %v; want nil, true`, got, ok)
	}
	if _, ok := o.Get("c"); ok {
		t.Error(`Get("c") found a key the object does not have`)
	}
}

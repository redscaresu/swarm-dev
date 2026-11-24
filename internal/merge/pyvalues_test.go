package merge

import (
	"errors"
	"math"
	"strings"
	"testing"
)

// pyCases are python3 3.14's str() and repr() of json.loads(text), as a generator printed them
// (the PR that added this file shows it and its run). A string holding a lone surrogate is its
// three bytes, as the decoder keeps it.
var pyCases = []struct{ text, str, repr string }{
	{`null`, "None", "None"},
	{`true`, "True", "True"},
	{`false`, "False", "False"},
	{`5`, "5", "5"},
	{`-0`, "0", "0"},
	{`5.0`, "5.0", "5.0"},
	{`1e16`, "1e+16", "1e+16"},
	{`1e-5`, "1e-05", "1e-05"},
	{`0.1`, "0.1", "0.1"},
	{`-0.0`, "-0.0", "-0.0"},
	{`1180591620717411303424`, "1180591620717411303424", "1180591620717411303424"},
	{`NaN`, "nan", "nan"},
	{`Infinity`, "inf", "inf"},
	{`-Infinity`, "-inf", "-inf"},
	{`1e400`, "inf", "inf"},
	{`1e15`, "1000000000000000.0", "1000000000000000.0"},
	{`0.0001`, "0.0001", "0.0001"},
	{`123.456`, "123.456", "123.456"},
	{`5e-324`, "5e-324", "5e-324"},
	{`1.7976931348623157e308`, "1.7976931348623157e+308", "1.7976931348623157e+308"},
	{`"it's"`, "it's", "\"it's\""},
	{`"say \"hi\""`, "say \"hi\"", "'say \"hi\"'"},
	{`"it's \"x\""`, "it's \"x\"", "'it\\'s \"x\"'"},
	{`"a\nb"`, "a\nb", "'a\\nb'"},
	{`"\u0001"`, "\x01", "'\\x01'"},
	{`"café"`, "café", "'café'"},
	{`"😀"`, "😀", "'😀'"},
	{`"\ud83d\ude00"`, "😀", "'😀'"},
	{`"\t\r\\ \/"`, "\t\r\\ /", "'\\t\\r\\\\ /'"},
	{`"\u007f \u00a0 \u200b \u2028"`, "\x7f \u00a0 \u200b \u2028", "'\\x7f \\xa0 \\u200b \\u2028'"},
	{`"\ud800"`, "\xed\xa0\x80", "'\\ud800'"},
	{`"\udc00\ud800"`, "\xed\xb0\x80\xed\xa0\x80", "'\\udc00\\ud800'"},
	{`[1, [2.5, "x"], []]`, "[1, [2.5, 'x'], []]", "[1, [2.5, 'x'], []]"},
	{`{"b": 1, "a": [null, true]}`, "{'b': 1, 'a': [None, True]}", "{'b': 1, 'a': [None, True]}"},
	{`{"a": 1, "b": 2, "a": 3}`, "{'a': 3, 'b': 2}", "{'a': 3, 'b': 2}"},
	{`{}`, "{}", "{}"},
	{`[]`, "[]", "[]"},
}

// TestStrReprMatchPython goes red when Str or Repr writes a value other than as python3's %s and %r
// do (a quote choice, an escape, a float's form, a key out of order), or the decoder reads a text
// other than as json.loads does.
func TestStrReprMatchPython(t *testing.T) {
	for _, c := range pyCases {
		v, err := Loads(c.text)
		if err != nil {
			t.Errorf("Loads(%q): %v", c.text, err)
			continue
		}
		if got := Str(v); got != c.str {
			t.Errorf("Str(Loads(%q)) = %q, want %q", c.text, got, c.str)
		}
		if got := Repr(v); got != c.repr {
			t.Errorf("Repr(Loads(%q)) = %q, want %q", c.text, got, c.repr)
		}
	}
	// A byte that is not UTF-8 is the surrogate Python's surrogateescape reads it as, in argv.
	if got, want := Repr([]any{"\xff", 7}), `['\udcff', 7]`; got != want {
		t.Errorf("Repr = %q, want %q", got, want)
	}
}

// TestDumpsMatchesPython goes red when Dumps writes other bytes than python3's json.dumps of the same
// value: HTML escaping, a separator, an ensure_ascii escape or a surrogate pair. Each want is the
// generator's. Each want also reads back to the same bytes, as python3 checked it does.
func TestDumpsMatchesPython(t *testing.T) {
	record := func(pid, want any) *Object {
		o := &Object{}
		for _, k := range []string{"repo", "base", "sha", "pr"} {
			o.Set(k, map[string]string{"repo": "o/r", "base": "main", "sha": "abc", "pr": "12"}[k])
		}
		o.Set("pid", pid)
		o.Set("want", want)
		return o
	}
	cases := []struct {
		name string
		v    any
		want string
	}{
		{"pages argv", []any{[]string{"api", "--paginate", "repos/o/r/commits/0123abc/check-runs?per_page=100&filter=latest"}, ""},
			`[["api", "--paginate", "repos/o/r/commits/0123abc/check-runs?per_page=100&filter=latest"], ""]`},
		{"non-ASCII argument", []any{[]string{"api", "repos/o/r/contents/docs/café.md?ref=main"}, ".[0]"},
			`[["api", "repos/o/r/contents/docs/caf\u00e9.md?ref=main"], ".[0]"]`},
		{"emoji", []string{"😀 ship it"}, `["\ud83d\ude00 ship it"]`},
		{"record", record(4242, nil),
			`{"repo": "o/r", "base": "main", "sha": "abc", "pr": "12", "pid": 4242, "want": null}`},
		{"record with want", record(Int("1180591620717411303424"), []string{".github/workflows/ci.yml", "x.yml"}),
			`{"repo": "o/r", "base": "main", "sha": "abc", "pr": "12", "pid": 1180591620717411303424, "want": [".github/workflows/ci.yml", "x.yml"]}`},
		{"escapes", []string{`<a href="x">&amp;</a>`, "\\ / \b\f\n\r\t \x01 \x7f é \u2028"},
			`["<a href=\"x\">&amp;</a>", "\\ / \b\f\n\r\t \u0001 \u007f \u00e9 \u2028"]`},
		{"scalars", []any{true, false, nil, Int("0"), -7, 1.5, 1e16, 1e-5, math.NaN(), math.Inf(1), math.Inf(-1), []any{}, &Object{}},
			`[true, false, null, 0, -7, 1.5, 1e+16, 1e-05, NaN, Infinity, -Infinity, [], {}]`},
		{"lone surrogates", []string{"\xed\xa0\x80", "\xff"}, `["\ud800", "\udcff"]`},
	}
	for _, c := range cases {
		if got := Dumps(c.v); got != c.want {
			t.Errorf("%s: Dumps = %s, want %s", c.name, got, c.want)
		}
		v, err := Loads(c.want)
		if err != nil {
			t.Errorf("%s: Loads: %v", c.name, err)
		} else if got := Dumps(v); got != c.want {
			t.Errorf("%s: Dumps(Loads) = %s, want %s", c.name, got, c.want)
		}
	}
}

// TestLoadsRefuses goes red when the decoder takes a text python3's json.loads raised ValueError on
// (the generator checked each), which ci_gate.py reads as an unreadable answer.
func TestLoadsRefuses(t *testing.T) {
	texts := []string{
		"[1,]", `{"a": 1,}`, "tru", "True", "nul", "01", "1.", ".5", "-", "+1", "-NaN", "1 2", "", " ",
		`"a`, "\"\x01\"", `"\q"`, `"\u12"`, `"\uZZZZ"`, `"\ud800\uZZZZ"`, "{1: 2}", `{"a" 1}`, "[1 2]",
		"\ufeff1", "1\x0c", strings.Repeat("1", 4301), "-" + strings.Repeat("1", 4301),
		"\"caf\xe9\"", // not UTF-8: Python fails to decode it before json.loads runs
	}
	for _, text := range texts {
		if v, err := Loads(text); !errors.Is(err, ErrNotJSON) {
			t.Errorf("Loads(%q) = %v, %v; want ErrNotJSON", text, v, err)
		}
	}
}

// TestLoadsKeepsTypes goes red when the decoder reads a value as another type than json.loads does:
// 5 as a float, 5.0 as an int, an int past int64 or of 4300 digits as anything but its digits.
func TestLoadsKeepsTypes(t *testing.T) {
	digits := strings.Repeat("9", 4300)
	cases := []struct {
		text string
		want any
	}{
		{"5", Int("5")}, {"5.0", 5.0}, {"5e0", 5.0}, {"-0", Int("0")}, {"-12", Int("-12")},
		{"1180591620717411303424", Int("1180591620717411303424")}, {digits, Int(digits)}, {"-" + digits, Int("-" + digits)},
		{"true", true}, {"null", nil}, {`"5"`, "5"},
	}
	for _, c := range cases {
		if got, err := Loads(c.text); err != nil || got != c.want {
			t.Errorf("Loads(%.20s) = %T %.20v, %v; want %T %.20v", c.text, got, got, err, c.want, c.want)
		}
	}
	o, err := Loads(`{"a": 1, "b": 2, "a": 3}`)
	if err != nil {
		t.Fatal(err)
	}
	if v, ok := o.(*Object).Get("a"); !ok || v != Int("3") {
		t.Errorf(`Get("a") = %v, %v; want 3, true (the last value given)`, v, ok)
	}
	if v, ok := o.(*Object).Get("c"); ok || v != nil {
		t.Errorf(`Get("c") = %v, %v; want nil, false`, v, ok)
	}
}

// TestRawDecode goes red when RawDecode reads past its value, skips whitespace at its offset (Python's
// raw_decode does not), or ends at another offset than python3's raw_decode gave: 10 and 14.
func TestRawDecode(t *testing.T) {
	text := `{"a": [1]} [2]`
	for _, c := range []struct {
		at, end int
		repr    string
	}{{0, 10, "{'a': [1]}"}, {11, 14, "[2]"}} {
		v, end, err := RawDecode(text, c.at)
		if err != nil || end != c.end || Repr(v) != c.repr {
			t.Errorf("RawDecode(%d) = %s, %d, %v; want %s, %d", c.at, Repr(v), end, err, c.repr, c.end)
		}
	}
	for _, at := range []int{10, len(text), len(text) + 1, -1} {
		if _, _, err := RawDecode(text, at); !errors.Is(err, ErrNotJSON) {
			t.Errorf("RawDecode(%d): %v, want ErrNotJSON", at, err)
		}
	}
}

// TestLoadsDepth goes red when the decoder refuses the 100,000 levels python3 read, or reads past
// maxDepth, or calls that ErrNotJSON, which a caller would take as an unreadable answer.
func TestLoadsDepth(t *testing.T) {
	deep := strings.Repeat("[", maxDepth) + strings.Repeat("]", maxDepth)
	if _, err := Loads(deep); err != nil {
		t.Errorf("Loads at maxDepth: %v", err)
	}
	_, err := Loads(`{"a": ` + deep + `}`)
	if !errors.Is(err, ErrTooDeep) || errors.Is(err, ErrNotJSON) {
		t.Errorf("Loads past maxDepth: %v, want ErrTooDeep alone", err)
	}
}

package touchesrows

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

// pyLib is bin/lib from this package's folder, where go test runs the test.
var pyLib = filepath.Join("..", "..", "bin", "lib")

// pyWait bounds the one python3 run.
const pyWait = 60 * time.Second

// pyDriver runs each case on stdin through touches_rows.py and prints its result as one line of
// json.dumps(sort_keys=True). -I keeps PYTHONPATH and the current folder off sys.path, and -B
// writes no __pycache__ into bin/lib.
const pyDriver = `
import json, sys
sys.path.insert(0, sys.argv[1])
import touches_rows as t

def run(c):
    op = c["op"]
    if op == "pairs":
        out = dict(c["pre"] or {})
        t.pairs(c["lines"] or [], out, c["stop"])
        return out
    if op == "front":
        return t.front_text(c["text"])
    if op == "first":
        return t.first_word(c["part"])
    if op == "split":
        return c["text"].split()
    if op == "overlap":
        return t.overlap(tuple(c["a"]), tuple(c["b"]))
    if op == "deps":
        return sorted(t.deps(c["fm"] or {}))
    if op == "skip":
        return sorted(t.SKIP_WORDS)
    raise SystemExit("unknown op " + op)

for c in json.load(sys.stdin):
    print(json.dumps(run(c), sort_keys=True))
`

// tcase is one input both sides run. Op names the rule: pairs (Lines, Stop, with Pre already in
// out), front (Text), first (Part), split (Text, as Python's str.split()), overlap (A, B), deps
// (FM) and skip (SkipWords itself).
type tcase struct {
	Name  string            `json:"name"`
	Op    string            `json:"op"`
	Lines []string          `json:"lines"`
	Stop  *string           `json:"stop"`
	Pre   map[string]string `json:"pre"`
	Text  string            `json:"text"`
	Part  string            `json:"part"`
	A     []string          `json:"a"`
	B     []string          `json:"b"`
	FM    map[string]string `json:"fm"`
}

func str(s string) *string { return &s }

func front(name, text string) tcase { return tcase{Name: name, Op: "front", Text: text} }
func first(name, part string) tcase { return tcase{Name: name, Op: "first", Part: part} }
func deps(name, v string) tcase {
	return tcase{Name: name, Op: "deps", FM: map[string]string{"depends_on": v}}
}
func overlap(name string, a, b Entry) tcase {
	return tcase{Name: name, Op: "overlap", A: []string{a.Repo, a.File, a.Part}, B: []string{b.Repo, b.File, b.Part}}
}

// item is a story file as tests/board_state_test.sh's item writes it.
func item(slug string, lines ...string) string {
	return "---\n" + strings.Join(lines, "\n") + "\n---\n\n# " + slug + "\n"
}

// storyB is story b as tests/concurrency_check_test.sh's idle writes it.
func storyB(touches, extra string) string {
	s := "---\nstatus: blocked\nkind: code\ndepends_on: [a]\ntouches: [" + touches + "]\n"
	if extra != "" {
		s += extra + "\n"
	}
	return s + "---\n\n# b\n"
}

// everyRune is each code point from U+0001 to U+FFFF but the surrogates, and a few past U+FFFF,
// each followed by x: str.split() splits it on exactly the code points Python counts as space.
func everyRune() string {
	var b strings.Builder
	for r := rune(1); r <= 0xffff; r++ {
		if utf8.ValidRune(r) {
			b.WriteRune(r)
			b.WriteByte('x')
		}
	}
	for _, r := range []rune{0x10000, 0x1f600, 0xe0020, 0x10ffff} {
		b.WriteRune(r)
		b.WriteByte('x')
	}
	return b.String()
}

func cases() []tcase {
	aStory := "---\nstatus: ready\nkind: code\ntouches: [x.sh:f run, y.sh]\n---\n\n# a\n"
	x := func(part string) Entry { return Entry{File: "x.sh", Part: part} }
	return []tcase{
		// front matter
		front("CRLF", "---\r\nstatus: ready\r\nkind: code\r\n---\r\n\r\n# a\r\n"),
		front("two CRs before each LF", "---\r\r\nk: v\r\r\n---\r\r\nafter: x\n"),
		front("no closing ---", "---\nstatus: ready\nkind: code\n\n# a: title\nbody: x\n"),
		front("first line not ---", "\n---\nstatus: ready\n---\n"),
		front("first line --- with a trailing space", "--- \nstatus: ready\n---\n"),
		front("first line --- with a leading space", " ---\nstatus: ready\n---\n"),
		front("repeated keys: the first wins", "---\nstatus: ready\nstatus: done\nkind: code\nkind:\n---\n"),
		front("a key with no value", "---\nheld_by:\nprs:   \nepic: \n---\n"),
		front("leading spaces dropped, a tab and trailing spaces kept", "---\nstatus:    ready  \nrepo:\t x\n---\n"),
		front("a line with no colon, a key with spaces, an empty key", "---\nno colon here\na b: c\n: empty key\n  k: v\n---\n"),
		front("a colon in the value", "---\ntouches: [x.sh:f run, y.sh]\nk: a: b\n---\n"),
		front("keys after the closing --- ignored", "---\nk: v\n---\nafter: x\n---\nlater: y\n"),
		front("empty text", ""),
		front("--- alone", "---"),
		front("--- and a newline", "---\n"),
		front("non-ASCII keys and values", "---\nnoté: café\n§ k:  v\n---\n"),
		front("board_state's t, a trailing space in status", item("t", "status: ready ", "kind: code", "touches: [lib.sh]")),
		front("board_state's o", item("o", "status: ready", "kind: code", "touches: [lib.sh]")),
		front("board_state's kid", item("kid", "status: ready", "kind: code", "depends_on: [par]")),
		front("concurrency's a", aStory),
		front("concurrency's b on x.sh:f check", storyB("x.sh:f check", "")),
		front("concurrency's b on c.sh, with needs", storyB("c.sh", "needs: a (its run flag)")),

		// pairs
		{Name: "pairs with no stop, a state file", Op: "pairs", Lines: []string{"status: review", "status@base: ready", "", "prs: u/1"}},
		{Name: "pairs keeps a key already in out", Op: "pairs", Lines: []string{"status: done", "kind: code"}, Pre: map[string]string{"status": "ready"}},
		{Name: "pairs stops at its stop line", Op: "pairs", Lines: []string{"a: 1", "---", "b: 2"}, Stop: str("---")},
		{Name: "pairs with a stop never seen", Op: "pairs", Lines: []string{"a: 1", "-- -", "b: 2"}, Stop: str("---")},
		{Name: "pairs with no stop reads past ---", Op: "pairs", Lines: []string{"a: 1", "---", "b: 2"}},
		{Name: "pairs with an empty stop", Op: "pairs", Lines: []string{"a: 1", "", "b: 2"}, Stop: str("")},
		{Name: "pairs over no lines", Op: "pairs"},

		// first word
		first("§ The x", "§ The x"),
		first("A, nothing past the skip words: the last word", "A"),
		first("Foo", "Foo"),
		first("foo", "foo"),
		first("THE Foo", "THE Foo"),
		first("the foo", "the foo"),
		first("a word split by U+001F", "f\x1frun"),
		first("the, then U+001C", "the\x1cfoo"),
		first("U+001D to U+001F before", "\x1d\x1e\x1fthe x"),
		first("empty: a bare file", ""),
		first("spaces only", " \t "),
		first("§ #: the last word", "§ #"),
		first("The A an: the last word", "The A an"),
		first("An alone", "An"),
		first("an x", "an x"),
		first("§The, no space", "§The x"),
		first("NBSP and ideographic space", "\u00a0the\u3000x"),
		first("a zero-width space is no space", "\u200bthe x"),
		first("Kelvin sign", "\u212a x"),
		first("dotted capital I", "\u0130 the"),
		first("concurrency's f run", "f run"),
		first("concurrency's f check", "f check"),

		// overlap
		overlap("bare file and bare file", x(""), x("")),
		overlap("bare file and a part of it", x(""), x("f run")),
		overlap("a part and its bare file", x("f run"), x("")),
		overlap("bare file and a part of skip words only", x(""), x("the")),
		overlap("same first word", x("f run"), x("f check")),
		overlap("different first words", x("g"), x("f run")),
		overlap("Foo and foo", x("Foo"), x("foo")),
		overlap("THE Foo and the foo", x("THE Foo"), x("the foo")),
		overlap("§ The x and x y", x("§ The x"), x("x y")),
		overlap("A and a", x("A"), x("a")),
		overlap("split by U+001F and by a space", x("f\x1frun"), x("f check")),
		overlap("another file", x("f run"), Entry{File: "y.sh", Part: "f run"}),
		overlap("another repo", x("f run"), Entry{Repo: "r", File: "x.sh", Part: "f run"}),
		overlap("bare files in two repos", Entry{Repo: "r", File: "y.sh"}, Entry{File: "y.sh"}),
		overlap("concurrency's c.sh and y.sh", Entry{File: "c.sh"}, Entry{File: "y.sh"}),

		// depends_on
		deps("[a]", "[a]"),
		deps("[a, b]", "[a, b]"),
		deps("a b", "a b"),
		deps("[a,b]", "[a,b]"),
		deps("quotes", `['a', "b"]`),
		deps("a comment", "[a] # after c"),
		deps("a comment with commas", "[a,b]  # c, d"),
		deps("only a comment", "#x"),
		deps("two #", "a#b#c"),
		deps("empty", ""),
		{Name: "no depends_on key", Op: "deps", FM: map[string]string{"status": "ready"}},
		deps("split by U+001F", "a\x1fb"),
		deps("split by NBSP", "a\u00a0b"),
		deps("a zero-width space is no split", "a\u200bb"),
		deps("board_state's kid", "[par]"),
		deps("separators only", " ,[]'\" "),
		deps("a trailing comma", "a,"),
		deps("a leading comma", ",a"),

		{Name: "SkipWords", Op: "skip"},
		{Name: "str.split over every code point", Op: "split", Text: everyRune()},
	}
}

// goRun runs c through the Go rules.
func goRun(t *testing.T, c tcase) string {
	t.Helper()
	switch c.Op {
	case "pairs":
		out := map[string]string{}
		for k, v := range c.Pre {
			out[k] = v
		}
		if c.Stop == nil {
			Pairs(c.Lines, out)
		} else {
			PairsUntil(c.Lines, out, *c.Stop)
		}
		return pyMap(out)
	case "front":
		return pyMap(FrontText(c.Text))
	case "first":
		if w := FirstWord(c.Part); w != "" {
			return pyList([]string{w})
		}
		return pyList(nil)
	case "split":
		return pyList(words(c.Text))
	case "overlap":
		return fmt.Sprint(Overlap(Entry{c.A[0], c.A[1], c.A[2]}, Entry{c.B[0], c.B[1], c.B[2]}))
	case "deps":
		return pyList(sortedKeys(Deps(c.FM)))
	case "skip":
		return pyList(sortedKeys(SkipWords))
	}
	t.Fatalf("case %q: unknown op %q", c.Name, c.Op)
	return ""
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys) // byte order of UTF-8 is code point order, as Python's sorted() uses
	return keys
}

// pyString is s as Python's json.dumps writes a str: ASCII only, with every character outside
// space to ~ escaped, and a character past U+FFFF as its UTF-16 surrogate pair, in lower-case hex.
func pyString(s string) string {
	named := map[rune]string{'"': `\"`, '\\': `\\`, '\n': `\n`, '\r': `\r`, '\t': `\t`, '\b': `\b`, '\f': `\f`}
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch e, ok := named[r]; {
		case ok:
			b.WriteString(e)
		case r >= ' ' && r <= '~':
			b.WriteRune(r)
		case r > 0xffff:
			r -= 0x10000
			fmt.Fprintf(&b, `\u%04x\u%04x`, 0xd800|r>>10, 0xdc00|r&0x3ff)
		default:
			fmt.Fprintf(&b, `\u%04x`, r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// pyList is a list of strings as json.dumps writes it.
func pyList(l []string) string {
	q := make([]string, len(l))
	for i, s := range l {
		q[i] = pyString(s)
	}
	return "[" + strings.Join(q, ", ") + "]"
}

// pyMap is a dict of strings as json.dumps(sort_keys=True) writes it.
func pyMap(m map[string]string) string {
	q := make([]string, 0, len(m))
	for _, k := range sortedKeys(m) {
		q = append(q, pyString(k)+": "+pyString(m[k]))
	}
	return "{" + strings.Join(q, ", ") + "}"
}

// clip shortens a long line for a failure message.
func clip(s string) string {
	if len(s) > 300 {
		return s[:300] + fmt.Sprintf("... (%d bytes)", len(s))
	}
	return s
}

// TestTextMatchesPython runs every case through touches_rows.py and through the Go, and wants the
// two outputs the same, byte for byte. With no python3, or a driver that fails, it fails: a skip
// would pass a Go copy nothing checked.
func TestTextMatchesPython(t *testing.T) {
	cs := cases()
	in, err := json.Marshal(cs)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pyWait)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-B", "-c", pyDriver, pyLib)
	cmd.Stdin = bytes.NewReader(in)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	py, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 over touches_rows.py: %v\n%s", err, stderr.String())
	}

	var goOut strings.Builder
	for _, c := range cs {
		goOut.WriteString(goRun(t, c) + "\n")
	}
	if string(py) == goOut.String() {
		return
	}
	pyLines, goLines := strings.Split(string(py), "\n"), strings.Split(goOut.String(), "\n")
	if len(pyLines) != len(goLines) {
		t.Errorf("python3 printed %d lines, the Go %d", len(pyLines), len(goLines))
	}
	for i, c := range cs {
		if i < len(pyLines) && i < len(goLines) && pyLines[i] != goLines[i] {
			t.Errorf("case %q (%s): python %s, go %s", c.Name, c.Op, clip(pyLines[i]), clip(goLines[i]))
		}
	}
}

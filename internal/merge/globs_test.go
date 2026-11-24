package merge

import (
	"errors"
	"testing"
)

// TestMatch holds glob and match to ci_gate.py's match: each want is what python3 3.14 printed for
// the same patterns and path.
func TestMatch(t *testing.T) {
	cases := []struct {
		name string
		pats []string
		s    string
		want bool
	}{
		{"* takes a file", []string{"docs/*"}, "docs/a.md", true},
		{"* stops at /", []string{"docs/*"}, "docs/a/b.md", false},
		{"** does not stop at /", []string{"docs/**"}, "docs/a/b.md", true},
		{"** alone takes any path", []string{"**"}, "a/b/c", true},
		{"**/ is zero folders", []string{"**/a.md"}, "a.md", true},
		{"**/ is several folders", []string{"**/a.md"}, "x/y/a.md", true},
		{"**/ ends at a /", []string{"**/a.md"}, "xa.md", false},
		{"**/ inside is zero folders", []string{"docs/**/a.md"}, "docs/a.md", true},
		{"**/ inside is several folders", []string{"docs/**/a.md"}, "docs/x/y/a.md", true},
		{"? takes none of what precedes", []string{"ab?c"}, "ac", true},
		{"? takes one of what precedes", []string{"ab?c"}, "abc", true},
		{"? takes no more than one", []string{"ab?c"}, "abbc", false},
		{"+ takes several of what precedes", []string{"ab+c"}, "abbbc", true},
		{"+ takes at least one", []string{"ab+c"}, "ac", false},
		{"a class takes its range", []string{"v[0-9].md"}, "v1.md", true},
		{"a class takes nothing outside it", []string{"v[0-9].md"}, "va.md", false},
		{"a negated class takes the rest", []string{"[^a]"}, "b", true},
		{"a negated class refuses its own", []string{"[^a]"}, "a", false},
		{". is a dot", []string{"a.b"}, "axb", false},
		{"regex characters are literal", []string{"(x)|{y}"}, "(x)|{y}", true},
		{"! after a hit drops it", []string{"docs/**", "!docs/*.md"}, "docs/a.md", false},
		{"! leaves what it misses", []string{"docs/**", "!docs/*.md"}, "docs/a.txt", true},
		{"the last match wins", []string{"docs/**", "!docs/*.md", "docs/keep.md"}, "docs/keep.md", true},
		{"a lone ! takes nothing", []string{"!docs/*.md"}, "src/a.go", false},
		{"only the first ! negates", []string{"!!a"}, "!a", false},
		{"no patterns take nothing", nil, "x", false},
		{"* takes a newline", []string{"*"}, "a\nb", true},
		{"** does not take a newline", []string{"**"}, "a\nb", false},
		{"? repeats a whole character, none", []string{"é?x"}, "x", true},
		{"? repeats a whole character, one", []string{"é?x"}, "éx", true},
		// A [] token leaves the class open, so a-z is in it: re.escape's \- keeps it from being a range.
		{"a class left open keeps - literal", []string{"[]a-z[q]"}, "m", false},
		{"a class left open takes -", []string{"[]a-z[q]"}, "-", true},
		{"*? is lazy, and both read it", []string{"docs/*?"}, "docs/a", true},
		{"a punctuation escape in a class", []string{`[\-x]`}, "-", true},
		{"a \\xHH escape in a class", []string{`[\x41]`}, "A", true},
		{"a \\t escape in a class", []string{`[\t]`}, "\t", true},
	}
	for _, c := range cases {
		got, err := match(c.s, c.pats)
		if err != nil || got != c.want {
			t.Errorf("%s: match(%q, %q) = %v, %v; want %v", c.name, c.s, c.pats, got, err, c.want)
		}
	}
}

// TestGlobBadPattern holds what glob refuses: each is a *badPattern naming the pattern, with this
// text. py is how ci_gate.py reads it, on python3 3.14 and on 3.9 where they differ.
func TestGlobBadPattern(t *testing.T) {
	cases := []struct {
		pattern string
		py      string
		want    string
	}{
		{"docs/*+", "3.14: possessive, takes docs/x; 3.9: multiple repeat",
			"invalid nested repetition operator: `*+`"},
		{"docs/**+", "3.14: possessive, takes docs/x; 3.9: multiple repeat",
			"invalid nested repetition operator: `*+`"},
		{"a?+", "3.14: possessive, takes a; 3.9: multiple repeat", "invalid nested repetition operator: `?+`"},
		{"a++", "3.14: possessive, takes a; 3.9: multiple repeat", "invalid nested repetition operator: `++`"},
		{"**/+", "3.14: possessive, takes a/; 3.9: multiple repeat", "invalid nested repetition operator: `?+`"},
		{"docs/[abc", "drops the [, takes docs/abc", "a [ with no ] after it"},
		{"[z-a]", "bad character range z-a", "invalid character class range: `z-a`"},
		{"+a", "nothing to repeat", "missing argument to repetition operator: `+`"},
		{`[\d]`, "takes the Arabic-Indic digit three", `RE2 reads \d in a class apart from Python's re, or not at all`},
		{`[\w]`, "takes é", `RE2 reads \w in a class apart from Python's re, or not at all`},
		{"[[:alpha:]]", "takes a]", "RE2 reads [: in a class as a POSIX class, where Python's re reads [ and :"},
		// A [] token, or a \] that ends one, leaves the class open into the next token, as both read it.
		{"[][:alpha:][x]", "takes ax: one class of ] [ : a l p h, then x",
			"RE2 reads [: in a class as a POSIX class, where Python's re reads [ and :"},
		{`[a\][:alpha:][x]`, "takes :x: one class of a ] [ : l p h, then x",
			"RE2 reads [: in a class as a POSIX class, where Python's re reads [ and :"},
		{`[\p{L}]`, `bad escape \p`, `RE2 reads \p in a class apart from Python's re, or not at all`},
		{`[\x{41}]`, `incomplete escape \x`, `RE2 reads \x in a class apart from Python's re, or not at all`},
		{`[\101]`, "takes A", `RE2 reads \1 in a class apart from Python's re, or not at all`},
	}
	for _, c := range cases {
		re, err := glob(c.pattern)
		var bad *badPattern
		if !errors.As(err, &bad) {
			t.Errorf("glob(%q) = %v, %v; want a *badPattern (python: %s)", c.pattern, re, err, c.py)
			continue
		}
		if bad.pattern != c.pattern || bad.why != c.want {
			t.Errorf("glob(%q): badPattern{%q, %q}; want {%q, %q}", c.pattern, bad.pattern, bad.why, c.pattern, c.want)
		}
	}
	if got, want := (&badPattern{"docs/*+", "why"}).Error(), `bad filter pattern "docs/*+": why`; got != want {
		t.Errorf("Error() = %q; want %q", got, want)
	}
}

// TestMatchReadsEveryPattern holds match to Python's loop, which reads every pattern even after a
// hit: a bad one later in the list is the error.
func TestMatchReadsEveryPattern(t *testing.T) {
	_, err := match("x", []string{"x", "[z-a]"})
	var bad *badPattern
	if !errors.As(err, &bad) || bad.pattern != "[z-a]" {
		t.Errorf(`match("x", [x [z-a]]) error = %v; want the badPattern of [z-a]`, err)
	}
}

// TestCovers holds covers to ci_gate.py's covers: each want is what python3 3.14 printed for the
// same filters, base and files ("error" where it raised re.error).
func TestCovers(t *testing.T) {
	known := func(paths ...string) fileList { return fileList{paths: paths, known: true} }
	cases := []struct {
		name  string
		f     map[string][]string
		base  string
		files fileList
		want  string
	}{
		{"branches main", map[string][]string{"branches": {"main"}}, "main", known("a"), "true"},
		{"branches dev", map[string][]string{"branches": {"main"}}, "dev", known("a"), "false"},
		{"branches glob", map[string][]string{"branches": {"release/*"}}, "release/1", known("a"), "true"},
		{"branches empty list", map[string][]string{"branches": {}}, "main", known("a"), "false"},
		{"branches-ignore dev", map[string][]string{"branches-ignore": {"dev"}}, "dev", known("a"), "false"},
		{"branches-ignore main", map[string][]string{"branches-ignore": {"dev"}}, "main", known("a"), "true"},
		{"tags only", map[string][]string{"tags": {"v*"}}, "main", known("a"), "false"},
		{"tags-ignore only", map[string][]string{"tags-ignore": {"v*"}}, "main", known("a"), "false"},
		{"tags with branches", map[string][]string{"tags": {"v*"}, "branches": {"main"}}, "main", known("a"), "true"},
		{"paths one hit", map[string][]string{"paths": {"docs/**"}}, "main", known("bin/x", "docs/a.md"), "true"},
		{"paths no hit", map[string][]string{"paths": {"docs/**"}}, "main", known("bin/x"), "false"},
		{"paths none changed", map[string][]string{"paths": {"docs/**"}}, "main", known(), "false"},
		{"paths-ignore every file", map[string][]string{"paths-ignore": {"docs/**"}}, "main", known("docs/a.md", "docs/b.md"), "false"},
		{"paths-ignore one not", map[string][]string{"paths-ignore": {"docs/**"}}, "main", known("docs/a.md", "bin/x"), "true"},
		{"paths-ignore none changed", map[string][]string{"paths-ignore": {"docs/**"}}, "main", known(), "false"},
		{"files None", map[string][]string{"paths": {"docs/**"}, "paths-ignore": {"**"}}, "main", fileList{}, "true"},
		{"f None", nil, "main", known("a"), "false"},
		{"f empty", map[string][]string{}, "main", known("a"), "true"},
		{"bad branches", map[string][]string{"branches": {"[z-a]"}}, "main", known("a"), "error"},
		{"bad paths, none changed", map[string][]string{"paths": {"[z-a]"}}, "main", known(), "false"},
		{"bad paths, unknown files", map[string][]string{"paths": {"[z-a]"}}, "main", fileList{}, "true"},
		{"bad branches-ignore after a miss", map[string][]string{"branches": {"dev"}, "branches-ignore": {"[z-a]"}}, "main", known("a"), "false"},
	}
	for _, c := range cases {
		ok, err := covers(c.f, c.base, c.files)
		got := map[bool]string{true: "true", false: "false"}[ok]
		var bad *badPattern
		if errors.As(err, &bad) {
			got = "error"
		} else if err != nil {
			got = err.Error()
		}
		if got != c.want {
			t.Errorf("%s: covers = %s; want %s", c.name, got, c.want)
		}
	}
}

// TestOnBoard holds onBoard to ci_gate.py's on_board on tests/merge_base_moved_test.sh's paths, over
// board_paths for a board at the root and for one in a folder named notes*.
func TestOnBoard(t *testing.T) {
	root := []string{"stories/", "epics/", "hld/", "Board.base", ".obsidian/", "retros/*.md"}
	notes := []string{"notes*/stories/", "notes*/epics/", "notes*/hld/", "notes*/Board.base", "notes*/.obsidian/", "notes*/retros/*.md"}
	cases := []struct {
		board []string
		p     string
		want  bool
	}{
		{root, "retros/v1.0.0.md", true},
		{root, "retros/x.sh", false},
		{root, "Board.base.py", false},
		{root, "Board.base", true},
		{root, "stories/a.md", true},
		{root, "epics", false},
		{notes, "notes*/retros/v1.0.0.md", true},
		{notes, "notes-x/retros/v1.0.0.md", false},
		{notes, "notes-other/Board.base", false},
		{notes, "notes*/Board.base", true},
		{notes, "notes*/retros/x.sh", false},
	}
	for _, c := range cases {
		if got := onBoard(c.p, c.board); got != c.want {
			t.Errorf("onBoard(%q, %q) = %v; want %v", c.p, c.board[0], got, c.want)
		}
	}
}

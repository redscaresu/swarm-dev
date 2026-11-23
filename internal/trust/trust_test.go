package trust

import (
	"errors"
	"io/fs"
	"strings"
	"testing"
)

// The folder most rows ask about, and its parent.
const (
	folder = "/w/f"
	parent = "/w"
)

// The read errors a row can give, as os.ReadFile returns them.
var (
	errIsDir   = &fs.PathError{Op: "read", Path: ".claude.json", Err: errors.New("is a directory")}
	errMissing = &fs.PathError{Op: "open", Path: ".claude.json", Err: fs.ErrNotExist}
)

// entry is a folder's entry whose trust field holds the JSON text v.
func entry(v string) string { return `{"` + trustKey + `": ` + v + `}` }

// trusting is a config whose projects object holds the JSON text members.
func trusting(members string) string { return `{"projects": {` + members + `}}` }

// trusted is a config that trusts the folder alone.
var trusted = trusting(`"` + folder + `": ` + entry("true"))

// nested is n arrays nested inside each other.
func nested(n int) string { return strings.Repeat("[", n) + strings.Repeat("]", n) }

// The rows of TestDecide. Each want is what `python3 bin/lib/require_trusted.py <root> <config>
// <git|>` exited on the same bytes, run by hand (Python 3.9.6 and 3.14.7, 2026-11-23); the PR that
// added this table has the runs. Letters (a) to (o) are trusted-tests-outside's cases.
var decideRows = []struct {
	name    string
	data    string
	readErr error
	root    string
	inGit   bool
	want    int
}{
	// Goes ahead: the file cannot be read, or is not JSON as Python reads it.
	{name: "(a) cut off", data: trusted[:len(trusted)-5], want: 0},
	{name: "(b) not UTF-8", data: trusting(`"/w/` + "\xff" + `": ` + entry("true")), want: 0},
	{name: "(c) a directory", readErr: errIsDir, want: 0},
	{name: "missing file", readErr: errMissing, want: 0},
	{name: "(d) UTF-8 BOM", data: "\xef\xbb\xbf" + trusting(""), want: 0},
	{name: "data after the value", data: trusting("") + " x", want: 0},
	{name: "a second value", data: trusting("") + " {}", want: 0},
	{name: "not JSON before deep nesting", data: "x" + nested(20000), want: 0},

	// Refused: nothing trusts the folder, or a value the rule reads is not an object.
	{name: "(e) no projects key", data: `{"other": 1}`, want: 1},
	{name: "(f) top level a list", data: "[" + trusted + "]", want: 1},
	{name: "(g) projects a list", data: `{"projects": []}`, want: 1},
	{name: "(h) folder entry null", data: trusting(`"` + folder + `": null`), want: 1},
	{name: "(i) trust 1", data: trusting(`"` + folder + `": ` + entry("1")), want: 1},
	{name: "(i) trust \"true\"", data: trusting(`"` + folder + `": ` + entry(`"true"`)), want: 1},

	// (j) A duplicate key keeps the last.
	{name: "(j) duplicate, true last", data: trusting(`"` + folder + `": ` + entry("false") + `, "` + folder + `": ` + entry("true")), want: 0},
	{name: "(j) duplicate, true first", data: trusting(`"` + folder + `": ` + entry("true") + `, "` + folder + `": ` + entry("false")), want: 1},

	// (k), (l) Python reads NaN, Infinity and 1e400, so a file that trusts nothing is refused.
	{name: "(k) NaN elsewhere", data: `{"projects": {}, "x": NaN}`, want: 1},
	{name: "(k) Infinity and -Infinity elsewhere", data: `{"projects": {}, "x": [Infinity, -Infinity]}`, want: 1},
	{name: "(l) 1e400 elsewhere", data: `{"projects": {}, "x": 1e400}`, want: 1},
	{name: "5000-digit integer elsewhere", data: `{"projects": {}, "x": ` + strings.Repeat("7", 5000) + `}`, want: 1},

	// Inside a string, NaN and brackets are text, past an escaped quote too.
	{name: "NaN in the folder's key", data: trusting(`"/w/NaN": ` + entry("true")), root: "/w/NaN", want: 0},
	{name: "brackets after an escaped quote", data: `{"projects": {}, "x": "\"` + strings.Repeat("[", 20000) + `"}`, want: 1},

	// (m) Paths are checked root first, so a trusted folder before a bad parent is trusted.
	{name: "(m) folder trusted, parent a list", data: trusting(`"` + folder + `": ` + entry("true") + `, "` + parent + `": []`), want: 0},
	{name: "(m) folder missing, parent a list", data: trusting(`"` + parent + `": []`), want: 1},

	// (n), (o) Deep nesting: Python's RecursionError is not caught, so it exits 1.
	{name: "(n) 500 deep elsewhere", data: `{"x": ` + nested(500) + `, "projects": {"` + folder + `": ` + entry("true") + `}}`, want: 0},
	{name: "(o) 200000 deep elsewhere", data: `{"x": ` + nested(200000) + `, "projects": {"` + folder + `": ` + entry("true") + `}}`, want: 1},
	{name: "200000 deep, cut off", data: strings.Repeat("[", 200000), want: 1},

	// Ancestors, outside git only, through Python's os.path.dirname.
	{name: "ancestor trusted outside git", data: trusting(`"` + parent + `": ` + entry("true")), want: 0},
	{name: "ancestor trusted inside git", data: trusting(`"` + parent + `": ` + entry("true")), inGit: true, want: 1},
	{name: "root trusted inside git", data: trusted, inGit: true, want: 0},
	{name: "'/a//b/' keeps its double slash", data: trusting(`"/a//b": ` + entry("true")), root: "/a//b/", want: 0},
	{name: "relative root reaches the empty path", data: trusting(`"": ` + entry("true")), root: "a/b", want: 0},

	// A lone surrogate escape in a key matches no UTF-8 root; a pair is the character.
	{name: "lone surrogate key", data: trusting(`"/w/\ud800": ` + entry("true")), root: "/w/\uFFFD", want: 1},
	{name: "surrogate pair key", data: trusting(`"/w/\ud83d\ude00": ` + entry("true")), root: "/w/\U0001F600", want: 0},
}

// TestDecide pins Decide to require_trusted.py's exit code on each row's bytes. If the Go reads
// .claude.json or walks the paths any other way than the Python does, a row goes red.
func TestDecide(t *testing.T) {
	for _, row := range decideRows {
		t.Run(row.name, func(t *testing.T) {
			root := row.root
			if root == "" {
				root = folder
			}
			if got := Decide([]byte(row.data), row.readErr, root, row.inGit); got != row.want {
				t.Errorf("Decide(root %q, git %v) = %d, want %d", root, row.inGit, got, row.want)
			}
		})
	}
}

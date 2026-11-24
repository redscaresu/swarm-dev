package report

import (
	"context"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// pyTimeout bounds the one python3 run the comparison makes.
const pyTimeout = 60 * time.Second

// fixesPy runs report.py's fixes_pr over each case's text, key and by, and prints True or False a line.
const fixesPy = `import json, sys
sys.path.insert(0, sys.argv[1])
import report
for text, key, by in json.load(sys.stdin):
    print(report.fixes_pr(text, key, by))
`

// fixCase is one fixes_pr call. want is what both sides must say, so a case that stops testing what
// its name says fails too.
type fixCase struct {
	name, text, key, by string
	want                bool
}

// The repo of most cases, a PR of it and one of another repo.
const (
	key1  = "o/r#1"
	inBy  = "o/r#2"
	outBy = "p/q#9"
)

// reach is a verb, n characters, and #1: the verb ends n characters before #1.
func reach(n int, fill string) string {
	return "fix" + strings.Repeat(fill, n) + "#1"
}

var fixCases = []fixCase{
	{"fixes #1 and not #4: #1", "Fixes #1 and doesn't fix #4", key1, inBy, true},
	{"fixes #1 and not #4: #4", "Fixes #1 and doesn't fix #4", "o/r#4", inBy, false},
	{"a URL from another repo", "Fix https://github.com/o/r/pull/3 for good", "o/r#3", outBy, true},
	{"a URL in another case", "fixes GitHub.com/O/R/pull/3", "o/r#3", outBy, true},
	{"owner/repo#N from another repo", "Fixes o/r#5", "o/r#5", outBy, true},
	{"a bare #N in the same repo", "Fixes #5", "o/r#5", inBy, true},
	{"a bare #N from another repo", "Fixes #5", "o/r#5", outBy, false},
	{"#12 against #123", "Fixes #123", "o/r#12", inBy, false},
	{"#12 against o/r#123", "Fixes o/r#123", "o/r#12", outBy, false},
	{"#12 then a sentence end", "Fixes #12.", "o/r#12", inBy, true},
	{"#1 against #10 as owner/repo", "Fixes o/r#10", key1, outBy, false},
	{"#1 then a Unicode digit", "Fixes #1٣", key1, inBy, false},
	{"a stacked-on clause", "Stacked on #1, fixes #1", key1, inBy, false},
	{"a stacked-on sentence, then a fix", "Stacked on #1. Fixes #1", key1, inBy, true},
	{"merge after", "Merge after #1, fixes #1", key1, inBy, false},
	{"merged origin/main", "Merged origin/main and fixes #1", key1, inBy, false},
	{"depends on, then a semicolon", "Depends on #2; fixes #1", key1, inBy, true},
	{"stacked onto is no stacked on", "Stacked onto it, fixes #1", key1, inBy, true},
	{"a sentence end before #N", "Fixes the docs. See #1", key1, inBy, false},
	{"a point with no space after it", "Fixes the docs.See #1", key1, inBy, true},
	{"a version number", "Fixes v1.2 in #1", key1, inBy, true},
	{"an exclamation mark", "Fixes it! #1", key1, inBy, false},
	{"a question mark", "Fixes it? #1", key1, inBy, false},
	{"a semicolon", "Fixes it; #1", key1, inBy, false},
	{"a line break", "Fixes it\n#1", key1, inBy, false},
	{"a no-break space after a point", "Fixes it. #1", key1, inBy, false},
	{"a separator after a point", "Fixes it.\x1c#1", key1, inBy, false},
	{"a zero-width space after a point", "Fixes it.​#1", key1, inBy, true},
	{"words between the verb and #N", "Fixes the flaky test in #1", key1, inBy, true},
	{"a verb 40 characters back", reach(40, " "), key1, inBy, true},
	{"a verb 41 characters back", reach(41, " "), key1, inBy, false},
	{"40 characters of emoji back", reach(40, "🙂"), key1, inBy, true},
	{"a verb 40 characters back past words", "Fixes the flaky test that the last PRs broke #1", key1, inBy, true},
	{"the nearest verb governs, past reach", "fix and fix" + strings.Repeat(" ", 41) + "#1", key1, inBy, false},
	{"a Unicode letter before #N", "Fixes é#1", key1, inBy, false},
	{"a letter before #N", "Fixes x#1", key1, inBy, false},
	{"a hash before #N", "Fixes ##1", key1, inBy, false},
	{"a slash before #N", "Fixes a/#1", key1, inBy, false},
	{"a bracket before #N", "Fixes (#1)", key1, inBy, true},
	{"a letter before owner/repo#N", "Fixes xo/r#1", key1, outBy, false},
	{"a Unicode letter before owner/repo#N", "Fixes éo/r#1", key1, outBy, false},
	{"a point before owner/repo#N", "Fixes my.o/r#1", key1, outBy, false},
	{"a hyphen before owner/repo#N", "Fixes -o/r#1", key1, outBy, false},
	{"a bracket before owner/repo#N", "Fixes (o/r#1)", key1, outBy, true},
	{"a Unicode letter before the verb", "éfix #1", key1, inBy, false},
	{"a Unicode letter after the verb", "fixé #1", key1, inBy, false},
	{"prefix is no fix", "prefix #1", key1, inBy, false},
	{"fixesx is no fix", "fixesx #1", key1, inBy, false},
	{"hotfix", "Hotfix for #1", key1, inBy, true},
	{"hot-fix", "hot-fix #1", key1, inBy, true},
	{"bugfix", "bugfix: #1", key1, inBy, true},
	{"quick-fix", "Quick-fix #1", key1, inBy, true},
	{"fixing", "Fixing #1", key1, inBy, true},
	{"fixed", "FIXED #1", key1, inBy, true},
	{"rework of", "Rework of #1", key1, inBy, true},
	{"regression from", "Regression from #1", key1, inBy, true},
	{"regression in", "regression in #1", key1, inBy, true},
	{"regression into is none", "regression into #1", key1, inBy, false},
	{"a dotless i", "fıxes #1", key1, inBy, true},
	{"a dotted capital I", "FİX #1", key1, inBy, true},
	{"a long s in stacked on", "ſtacked on #1, fixes #1", key1, inBy, false},
	{"a Kelvin sign in quickfix", "quicKfix #1", key1, inBy, true},
	{"not fixing", "Not fixing #1", key1, inBy, false},
	{"never fixed", "never fixed #1", key1, inBy, false},
	{"no longer fixes", "No longer fixes #1", key1, inBy, false},
	{"doesn't yet fix", "doesn't yet fix #1", key1, inBy, false},
	{"isn't quite yet fixing", "isn't quite yet fixing #1", key1, inBy, true},
	{"cannot fix", "cannot fix #1", key1, inBy, true},
	{"a curly apostrophe", "doesn’t fix #1", key1, inBy, true},
	{"not, then a comma", "not, fix #1", key1, inBy, true},
	{"a Unicode space after not", "not fixing #1", key1, inBy, false},
	{"the nearest verb negated", "fixes the bug, does not fix #1", key1, inBy, false},
	{"a second mention fixed", "#1 was it: fixes #1", key1, inBy, true},
	{"a verb in another clause", "Fix the thing.\n#1", key1, inBy, false},
	{"no number in the key", "Fixes #1", "o/r", inBy, false},
	{"an empty number in the key", "Fixes #1", "o/r#", inBy, false},
	{"an empty text", "", key1, inBy, false},
	// The PR bodies tests/rework_test.sh's gh stub gives, as rework_of joins a title and body.
	{"rework_test: a fix of #1", "Fix a\nFixes #1.", key1, inBy, true},
	{"rework_test: a fix of #3 by its URL", "Fix https://github.com/o/r/pull/3\n", "o/r#3", "o/r#4", true},
	{"rework_test: a hotfix no build made", "Hotfix for #7\n", "o/r#7", "o/r#9", true},
	{"rework_test: a recent fix", "Fix #13\n", "o/r#13", "o/r#14", true},
	{"rework_test: a PR that fixes nothing", "a\n", key1, "o/r#3", false},
}

// pyFixes is report.py's fixes_pr over every case, one True or False a line.
func pyFixes(t *testing.T, cases []fixCase) string {
	t.Helper()
	args := make([][3]string, len(cases))
	for i, c := range cases {
		args[i] = [3]string{c.text, c.key, c.by}
	}
	in, err := json.Marshal(args)
	if err != nil {
		t.Fatal(err)
	}
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pyTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-c", fixesPy, lib)
	cmd.Stdin = strings.NewReader(string(in))
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 report.fixes_pr: %v\n%s", err, stderr.String())
	}
	return string(out)
}

// TestFixesPRMatchesPython fails when FixesPR and report.py's fixes_pr say different things about
// any case, byte for byte, or either says other than the case's want.
func TestFixesPRMatchesPython(t *testing.T) {
	var goOut strings.Builder
	for _, c := range fixCases {
		goOut.WriteString(map[bool]string{true: "True", false: "False"}[FixesPR(c.text, c.key, c.by)] + "\n")
	}
	py := pyFixes(t, fixCases)
	if py == goOut.String() {
		t.Logf("%d cases: report.py and the Go print the same", len(fixCases))
	}
	pyLines, goLines := strings.Split(py, "\n"), strings.Split(goOut.String(), "\n")
	for i, c := range fixCases {
		want := map[bool]string{true: "True", false: "False"}[c.want]
		p, g := "", goLines[i]
		if i < len(pyLines) {
			p = pyLines[i]
		}
		if p != g || g != want {
			t.Errorf("%s: %q key %s by %s: python %s, go %s, want %s", c.name, c.text, c.key, c.by, p, g, want)
		}
	}
	if py != goOut.String() {
		t.Errorf("report.py and the Go differ:\npython:\n%sgo:\n%s", py, goOut.String())
	}
}

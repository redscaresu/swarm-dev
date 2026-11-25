package report

import (
	"bufio"
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// pythonFindings reads one JSON case per line on stdin and writes, for each, what report.py's
// finding_rows or fixed_rows gave: the row count and the hex of the UTF-8 of the rows, columns joined
// by tab and rows by LF, or the name of the exception it raised. argv[1] is bin/lib.
const pythonFindings = `import json, os, sys
sys.path.insert(0, sys.argv[1])
from report import finding_rows, fixed_rows
for line in sys.stdin:
    c = json.loads(line)
    os.environ.pop("SWARM_FINDING_REVIEWERS", None)
    if c["env"] is not None:
        os.environ["SWARM_FINDING_REVIEWERS"] = c["env"]
    kw = {}
    if c["outcomes"] is not None:
        kw["outcomes"] = tuple(c["outcomes"])
    if c["width"]:
        kw["width"] = c["width"]
    try:
        rows = fixed_rows(c["path"]) if c["fixed"] else finding_rows(c["path"], **kw)
        text = "\n".join("\t".join(f) for f in rows)
        sys.stdout.write("%d:%s\n" % (len(rows), text.encode("utf-8").hex()))
    except KeyError:
        sys.stdout.write("KeyError\n")
    except OSError:
        sys.stdout.write("OSError\n")
`

// pythonTimeout bounds the one python3 run, which reads every case.
const pythonTimeout = 2 * time.Minute

// day is the date every fixture row carries; the readers never parse it.
const day = "2026-10-01"

// reviewerList is SWARM_FINDING_REVIEWERS as bin/swarm.sh sets it.
const reviewerList = "codex fallback code-review ci conductor lead skeptic critic split-critic escaped"

// findingsCase is one read: the file's bytes (or a missing file, or a folder), the reviewer list (nil
// for unset), and the call: fixed_rows, or finding_rows with outcomes and width (nil and 0 for
// Python's defaults).
type findingsCase struct {
	name     string
	file     string
	missing  bool
	folder   bool
	env      *string
	fixed    bool
	outcomes []string
	width    int
}

// wire is one case as the Python reads it.
type wire struct {
	Path     string   `json:"path"`
	Env      *string  `json:"env"`
	Fixed    bool     `json:"fixed"`
	Outcomes []string `json:"outcomes"`
	Width    int      `json:"width"`
}

// rows joins tab-separated columns into LF-ended rows dated day.
func rows(rs ...string) string {
	var b strings.Builder
	for _, r := range rs {
		b.WriteString(day + "\t" + r + "\n")
	}
	return b.String()
}

// env is a pointer to v, for a case's reviewer list.
func env(v string) *string { return &v }

// logFindingRows are tests/log_finding_test.sh's malformed rows: an 8-field row and its 9-field twin,
// the 9-field one with and without its newline, and a flattened tab, LF and CR.
var logFindingRows = rows(
	"k\to/r#96\tt\tdeclined\tcodex\tnit\t2",
	"k\to/r#96\tt\tdeclined\tcodex\tnit\t2\tthe builder says so",
	"k\to/r#97\tan edge case\tdeclined\tcodex\tout-of-scope\t2",
	"k\to/r#97\tan edge case\tdeclined\tcodex\tout-of-scope\t2\tthe builder says so",
	"k\to/r#94\tt\tdeclined\tcodex\twrong\t1\tone two three",
	"rev-kind\to/r#93\tt\tfixed\tunknown",
	"tab-test\to/r#7\ta b c\tfixed\tunknown",
	"cr-test\to/r#31\ta b \tfixed\tunknown",
) + day + "\tk\to/r#98\tno newline\tdeclined\tcodex\tnit\t2\tthe builder says so"

// recurringRows are tests/recurring_kinds_test.sh's fixed rows: 4-column rows, 6-column fixed,
// escaped and declined ones, the wide and wide-bogus rows of 4, 6 and 7 fields, and a bad byte.
var recurringRows = rows(
	"vacuous-test\to/r#1\t29 days old: inside the window",
	"vacuous-test\thttps://github.com/o/r/pull/1\tthe same PR again\tfixed\tcodex",
	"vacuous-test\to/r#2\tb\tfixed\tcodex",
	"vacuous-test\to/r#3\tc\tescaped\tunknown",
	"vacuous-test\to/r#4\tdeclined, no lesson\tdeclined\tcodex",
	"missing-check\to/r#20\ta",
	"two-prs\to/r#5\td",
	"wide\to/r#101\tx",
	"wide-bogus\to/r#101\tx",
	"wide\to/r#102\tx\tfixed\tcodex",
	"wide-bogus\to/r#102\tx\tfixed\tbogus",
	"wide\to/r#103\tx\tfixed\tunknown\ta later column",
	"wide-bogus\to/r#103\tx\tfixed\tunknown\ta later column",
	"bytes\to/r#111\tbad \xff byte",
	"bytes\to/r#112\tbad \xff byte",
)

// shapeRows are rows of every width from none to past maxCols, an empty line, a line of tabs alone, a
// 5-column row and each outcome.
var shapeRows = "\n" + day + "\n" + day + "\tk\n" + day + "\tk\to/r#1\n\t\t\t\n" + rows(
	"k\to/r#2\tfour",
	"k\to/r#3\tfive declined\tdeclined",
	"k\to/r#4\tfive escaped\tescaped",
	"k\to/r#5\tsix\tescaped\tcodex",
	"k\to/r#6\tseven\tdeclined\tlead\tnit",
	"k\to/r#7\teight\tdeclined\tci\tdeferred\t3",
	"k\to/r#8\tten\tfixed\tcritic\tr\t1\tnine\tten",
	"k\to/r#9\tbad outcome\tok\tcodex",
	"k\to/r#10\tempty outcome\t\tcodex",
	"k\to/r#11\tempty reviewer\tfixed\t",
)

// crlfRows end in CRLF: newline="\n" keeps the CR, so a 4-column row's text keeps it and a 6-column
// row's reviewer is "codex\r", no reviewer at all.
var crlfRows = day + "\tk\to/r#1\tcr text\r\n" + day + "\tk\to/r#2\tcr reviewer\tfixed\tcodex\r\n" +
	day + "\tk\to/r#3\tcr then tab\tfixed\tcodex\t\r\n" + day + "\tk\to/r#4\tlone\rcr\tfixed\tlead\n"

// badByteRows hold bad UTF-8 in each column the readers look at, and a sequence cut short at the end.
var badByteRows = rows(
	"k\xff\to/r#1\ttext",
	"k\to/r#2\ttruncated \xe2\x82\tfixed\tcodex",
	"k\to/r#3\tbad outcome\tfix\xc3\tcodex",
	"k\to/r#4\tbad reviewer\tfixed\tcod\xedx",
	"k\to/r#5\tsurrogate \xed\xa0\x80 and overlong \xc0\xaf\tescaped\tunknown",
) + "\xef\xbb\xbf" + day + "\tk\to/r#6\ta BOM first\n" + day + "\tk\to/r#7\tcut at the end \xf0\x9f\x98"

// unknownRows log a reviewer the list lacks, unknown itself, and an empty and a spaced one.
var unknownRows = rows(
	"k\to/r#1\tlisted\tfixed\tcodex",
	"k\to/r#2\tunknown\tfixed\tunknown",
	"k\to/r#3\tnot listed\tfixed\tbot",
	"k\to/r#4\tunknown, declined\tdeclined\tunknown",
	"k\to/r#5\ttwo in one\tfixed\tconductor lead",
	"k\to/r#6\tcase\tfixed\tCodex",
)

// findingsCases is every read the comparison runs.
func findingsCases() []findingsCase {
	list := env(reviewerList)
	files := []struct{ name, text string }{
		{"log_finding rows", logFindingRows}, {"recurring rows", recurringRows}, {"shapes", shapeRows},
		{"CRLF", crlfRows}, {"bad bytes", badByteRows}, {"unknown reviewer", unknownRows},
	}
	var out []findingsCase
	for _, f := range files {
		out = append(out,
			findingsCase{name: f.name + ", defaults", file: f.text, env: list},
			findingsCase{name: f.name + ", fixed_rows", file: f.text, env: list, fixed: true},
			findingsCase{name: f.name + ", width 7", file: f.text, env: list, width: 7},
			findingsCase{name: f.name + ", width 8", file: f.text, env: list, width: 8},
			findingsCase{name: f.name + ", width 9", file: f.text, env: list, width: 9},
			findingsCase{name: f.name + ", escaped", file: f.text, env: list, outcomes: []string{"escaped"}},
			findingsCase{name: f.name + ", three outcomes", file: f.text, env: list,
				outcomes: []string{"fixed", "declined", "escaped"}, width: 8},
			findingsCase{name: f.name + ", empty list", file: f.text, env: env("")},
			findingsCase{name: f.name + ", one reviewer", file: f.text, env: env("lead")},
			findingsCase{name: f.name + ", unset", file: f.text},
		)
	}
	return append(out,
		findingsCase{name: "separators U+001C to U+001F", file: unknownRows, env: env("bot\x1ccodex\x1dlead\x1estray\x1fx")},
		findingsCase{name: "no-break space and tabs", file: unknownRows, env: env(" \tbot\u00a0codex\n")},
		findingsCase{name: "empty file", file: "", env: list},
		findingsCase{name: "missing file", missing: true, env: list},
		findingsCase{name: "missing file, fixed_rows", missing: true, env: list, fixed: true},
		findingsCase{name: "missing file, unset", missing: true},
		findingsCase{name: "a folder", folder: true, env: list},
	)
}

// encode is what pythonFindings writes for rows, or for err.
func encode(got [][]string, err error) string {
	switch {
	case errors.Is(err, ErrNoReviewers):
		return "KeyError"
	case err != nil:
		return "OSError"
	}
	joined := make([]string, len(got))
	for i, f := range got {
		joined[i] = strings.Join(f, "\t")
	}
	return strconv.Itoa(len(got)) + ":" + hex.EncodeToString([]byte(strings.Join(joined, "\n")))
}

// readGo is what FindingRows or FixedRows gives for c, read through the real store.
func readGo(t *testing.T, c findingsCase, path string) string {
	t.Helper()
	t.Setenv(reviewersVar, "")
	if c.env == nil {
		if err := os.Unsetenv(reviewersVar); err != nil {
			t.Fatal(err)
		}
	} else {
		t.Setenv(reviewersVar, *c.env)
	}
	r := Findings{Store: store.Files{}}
	if c.fixed {
		return encode(r.FixedRows(path))
	}
	width := c.width
	if width == 0 {
		width = minWidth
	}
	return encode(r.FindingRows(path, c.outcomes, width))
}

// writeCases writes each case's file under dir and returns its path and the Python's input.
func writeCases(t *testing.T, dir string, cs []findingsCase) ([]string, []byte) {
	t.Helper()
	paths := make([]string, len(cs))
	var in bytes.Buffer
	for i, c := range cs {
		paths[i] = filepath.Join(dir, fmt.Sprintf("%d.tsv", i))
		switch {
		case c.folder:
			if err := os.Mkdir(paths[i], 0o700); err != nil {
				t.Fatal(err)
			}
		case !c.missing:
			if err := os.WriteFile(paths[i], []byte(c.file), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		line, err := json.Marshal(wire{Path: paths[i], Env: c.env, Fixed: c.fixed, Outcomes: c.outcomes, Width: c.width})
		if err != nil {
			t.Fatal(err)
		}
		in.Write(append(line, '\n'))
	}
	return paths, in.Bytes()
}

// runPython reads every case with report.py and returns one result line per case.
func runPython(t *testing.T, in []byte) []string {
	t.Helper()
	if _, err := exec.LookPath("python3"); err != nil {
		t.Fatalf("the comparison needs python3 on PATH, as report.py does: %v", err)
	}
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-c", pythonFindings, lib)
	cmd.Stdin = bytes.NewReader(in)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3: %v\n%s", err, stderr.String())
	}
	var lines []string
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(nil, 1<<20)
	for sc.Scan() {
		lines = append(lines, sc.Text())
	}
	return lines
}

// TestFindingsMatchPython checks FindingRows and FixedRows against report.py's finding_rows and
// fixed_rows, byte for byte, on every case: if a Go rule drifts from the Python (a default, the
// column cut, the decode, the reviewer list), this goes red.
func TestFindingsMatchPython(t *testing.T) {
	cs := findingsCases()
	paths, in := writeCases(t, t.TempDir(), cs)
	want := runPython(t, in)
	if len(want) != len(cs) {
		t.Fatalf("python3 gave %d results for %d cases", len(want), len(cs))
	}
	kept := 0
	for i, c := range cs {
		got := readGo(t, c, paths[i])
		if got != want[i] {
			t.Errorf("%s:\n  go     %s\n  python %s", c.name, got, want[i])
		}
		if !strings.HasPrefix(want[i], "0:") && strings.Contains(want[i], ":") {
			kept++
		}
	}
	// A comparison where every case gives no rows, or an error, would pass a reader that keeps nothing.
	if kept == 0 {
		t.Fatal("no case kept a row, so the comparison checks nothing")
	}
}

// TestFindingRowsNeedReviewers checks that both readers fail with SWARM_FINDING_REVIEWERS unset,
// for a file with rows and for a missing one: if the read moved after the stat, or defaulted to an
// empty list, a caller that forgot it would silently get no rows.
func TestFindingRowsNeedReviewers(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "findings.tsv")
	if err := os.WriteFile(path, []byte(rows("k\to/r#1\tt\tfixed\tunknown")), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(reviewersVar, "")
	if err := os.Unsetenv(reviewersVar); err != nil {
		t.Fatal(err)
	}
	r := Findings{Store: store.Files{}}
	for _, p := range []string{path, filepath.Join(dir, "missing.tsv")} {
		if got, err := r.FindingRows(p, nil, minWidth); !errors.Is(err, ErrNoReviewers) || got != nil {
			t.Errorf("FindingRows(%s) unset: got %q, %v; want nil, ErrNoReviewers", p, got, err)
		}
		if got, err := r.FixedRows(p); !errors.Is(err, ErrNoReviewers) || got != nil {
			t.Errorf("FixedRows(%s) unset: got %q, %v; want nil, ErrNoReviewers", p, got, err)
		}
	}
	t.Setenv(reviewersVar, "")
	got, err := r.FindingRows(path, nil, minWidth)
	want := [][]string{{day, "k", "o/r#1", "t", "fixed", "unknown"}}
	if err != nil || fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("FindingRows with an empty list: got %q, %v; want %q", got, err, want)
	}
}

// TestFindingRowsWidth checks that a width under minWidth is an error, not a panic on the reviewer
// column.
func TestFindingRowsWidth(t *testing.T) {
	t.Setenv(reviewersVar, reviewerList)
	r := Findings{Store: store.Files{}}
	if _, err := r.FindingRows(filepath.Join(t.TempDir(), "x.tsv"), nil, minWidth-1); err == nil {
		t.Errorf("FindingRows width %d: want an error", minWidth-1)
	}
}

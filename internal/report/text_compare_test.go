package report

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The zone both sides read local days in: UTC+14, so a time late in a UTC day falls on the next local
// day. A POSIX TZ string, so python3 needs no zone files, and a fixed zone in Go.
const (
	localTZ     = "<+14>-14"
	localOffset = 14 * 60 * 60
)

// pythonSeconds bounds the python3 run.
const pythonSeconds = 60

// textDriver runs report.py's text rules over the cases on stdin (JSON, textCases' fields) and prints
// what each gives as JSON. argv[1] is bin/lib. A merge time prints as its microseconds since the epoch,
// its offset in seconds and its local day; None prints as null.
const textDriver = `
import datetime, json, sys
sys.path.insert(0, sys.argv[1])
import report
c = json.load(sys.stdin)
EPOCH = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
def when(t):
    d = report.merge_time(t)
    if d is None:
        return None
    us = (d - EPOCH) // datetime.timedelta(microseconds=1)
    return "%d %d %s" % (us, d.utcoffset() // datetime.timedelta(seconds=1), report.local_day(d).isoformat())
def step(r):
    m = report.STEP_UP.fullmatch(r)
    return None if m is None else list(m.groups())
json.dump({
    "version": sys.version.split()[0],
    "agent_name_max": report.AGENT_NAME_MAX,
    "phases": list(report.PHASES),
    "pr_key": [report.pr_key(x) for x in c["pr_key"]],
    "agent_name": [report.agent_name(x) for x in c["agent_name"]],
    "cut_records": [report.cut_records(x) for x in c["cut_records"]],
    "step_up": [step(r) for r, _ in c["escalate"]],
    "escalate": [report.escalate_build(r, m) for r, m in c["escalate"]],
    "control": [report.CONTROL.sub("", x) for x in c["control"]],
    "merge_time": [when(t) for t in c["merge_time"]],
}, sys.stdout)
`

// textCases are the inputs both sides read. No Python test calls these functions alone, so the
// malformed cases are here.
type textCases struct {
	PRKey      []string    `json:"pr_key"`
	AgentName  []string    `json:"agent_name"`
	CutRecords [][]string  `json:"cut_records"`
	Escalate   [][2]string `json:"escalate"` // an escalate line and the escalate role's model
	Control    []string    `json:"control"`
	MergeTime  []string    `json:"merge_time"`
}

// textResults is what textDriver prints.
type textResults struct {
	Version      string               `json:"version"` // python3's, for a failure's log
	AgentNameMax int                  `json:"agent_name_max"`
	Phases       []string             `json:"phases"`
	PRKey        []string             `json:"pr_key"`
	AgentName    []string             `json:"agent_name"`
	CutRecords   []map[string]*string `json:"cut_records"`
	StepUp       [][]string           `json:"step_up"`
	Escalate     []bool               `json:"escalate"`
	Control      []string             `json:"control"`
	MergeTime    []*string            `json:"merge_time"`
}

var cases = textCases{
	PRKey: []string{
		"https://github.com/Owner/Repo/pull/12",
		"https://github.com/Owner/Repo/pull/12/files",
		"see https://github.com/a/b/pull/x, then https://github.com/C/D/pull/7",
		"xgithub.com/A/B/pull/5",
		"https://github.com/O/R/pull/١٢",   // Arabic-Indic digits, which Python's \d takes
		"https://github.com/O/R/pull/12٣4", // mixed digits
		"github.com/a/b/c/pull/1",
		"github.com/A B/C/pull/1",
		"github.com/A\u00a0B/C/pull/1", // a no-break space, which \s takes
		"github.com/A/B/pull/",
		"  Owner/Repo#34  ",
		"Owner/Repo#34\x1c", // a separator Python's \s takes and Go's unicode.IsSpace does not
		"Owner/Repo#34\n",
		"Owner/Repo#٣٤",
		"Owner/Repo #34",
		"owner/repo#34/",
		"a/b#c#1",
		"#1",
		"https://example.com/x/  ",
		"https://example.com/x//",
		"x /",
		"\x1cplain\x1c",
		"\u00a0plain\u3000",
		"",
		"İSTANBUL/Repo#1",
		"ΟΔΟΣ/ΡΣ#2",     // Σ ends both words
		"ΑΣΑ/b#3",       // Σ inside a word
		"Α'Σ/b#3",       // an apostrophe is case-ignorable
		"Α'Σ'Α/b#3",     // so this Σ is inside a word
		"Σ/b#3",         // nothing cased before it
		"\u212a/R#4",    // the Kelvin sign lowers to k
		"ǅungla/Repo#5", // a titlecase letter
	},
	AgentName: []string{
		"go-report-text", "Go_Report", "café", "İnci", "\u212aelvin", "123abc", "", "-x", "_x",
		strings.Repeat("a", 40), strings.Repeat("é", 40), "ÀBC", "a.b c", "x\u0307", "🚀go",
		"ΟΔΟΣ", strings.Repeat("ab", 15) + "İx",
	},
	CutRecords: [][]string{
		{strings.Repeat("a", 32) + "x", strings.Repeat("a", 32) + "y", "short", "short"},
		{"é", "-"},      // both give s-
		{"İ", "i-"},     // both give i-
		{"\u212a", "k"}, // both give k
		{"Abc", "abc", "other"},
		{"x"},
		{},
	},
	Escalate: [][2]string{
		{"ok (attempt 2)", "opus"},
		{"ok (attempt ٣)", "opus"},
		{"ok (attempt )", "opus"},
		{"ok (attempt 2) ", "opus"},
		{"ok (attempt 2)\n", "opus"},
		{"ok (stalled: sonnet -> opus)", "opus"},
		{"ok (stalled: opus -> sonnet)", "opus"},
		{"ok (findings-3: a -> b))", "b)"},
		{"ok (Stalled: a -> b)", "b"},
		{"ok (x: a\u00a0-> b)", "b"},
		{"ok (x: a -> b\x1c)", "b\x1c"},
		{"ok (x: a -> )", ""},
		{"ok (x:  -> b)", "b"},
		{"ok (x: a -> b)\n", "b"},
		{"ok (x: a -> b c)", "b c"},
		{"ok (: a -> b)", "b"},
		{"ok (ci-red-2: é -> ü)", "ü"},
		{"failed (attempt 1)", "opus"},
	},
	Control: []string{
		"plain", "tab\there", "\x00nul\x1fus\x7fdel\u0080c1\u009fend\u00a0nbsp", "é\u200bzw", "",
	},
	MergeTime: []string{
		"2026-11-24T10:00:00Z",
		"2026-11-24T10:30:00Z", // the next local day at UTC+14
		"2026-11-24T10:00:00+05:30",
		"2026-11-24T10:00:00-11:00",
		"2026-11-24T10:00:00-00:00",
		"2026-11-24T10:00:00", // no offset
		"2026-11-24",
		"2026-11-24T10Z",
		"2026-11-24T10:00Z",
		"2026-11-24 10:00:00.123+01:00",
		"2026-11-24T10:00:00.123456-03:00",
		"2026-11-24T10:00:00+23:59:59",
		"2026-11-24T10:00:00+24:00",
		"2026-11-24T10:00:00+01:00:30",
		"2026-11-24T10-01:00",
		"2026-11-24é10:00Z",
		"2024-02-29T10:00:00Z",
		"2026-02-29T10:00:00Z",
		"0000-01-01T00:00Z",
		"2026-13-01T00:00Z",
		"2026-11-24T25:00:00Z",
		"2026-11-24T10:60:00Z",
		"2026-11-24T10:00:60Z",
		"2026-11-24T10:00:00ZZ",
		"nonsense",
		"",
		"2026-11-24T",
		"2026-11-24T1Z",
		"2026-11-2410:00Z",
		"2026-11-24T١٠:00Z",
		"2026-1-24T10:00Z",
		"2026-11-24T10:00:00+01:00 ",
		"2026-11-24T10:00:00z",
		"2026-11-24T10:00:00+-01:00",
		"2026-11-24T10:00:00+1a:00",
		"2026-11-24T10:00:00+01:0",
		"2026-11-24T10:00:00é+01:00",
		"2026-11-24T10:00:00.123x+01:00",
		"2026-11-24T10:00:00xx+01:00",
	},
}

// runPython runs textDriver over cases under the python3 on PATH, with python3 -I so no
// PYTHONPATH or user site reaches it, and local days in localTZ.
func runPython(t *testing.T, in textCases) textResults {
	t.Helper()
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(lib, "report.py")); err != nil {
		t.Fatalf("report.py is not where the test looks: %v", err)
	}
	stdin, err := json.Marshal(in)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonSeconds*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-c", textDriver, lib)
	cmd.Env = append(os.Environ(), "TZ="+localTZ)
	cmd.Stdin = bytes.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 -I over report.py: %v\n%s", err, stderr.String())
	}
	var got textResults
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatalf("python3's output is not the results: %v\n%s", err, out)
	}
	return got
}

// same fails each place the Python and the Go differ, naming the part and the input.
func same[T comparable](t *testing.T, part string, inputs []string, py, goes []T) {
	t.Helper()
	if len(py) != len(goes) {
		t.Errorf("%s: python3 gave %d results and the Go %d", part, len(py), len(goes))
		return
	}
	for i := range py {
		if py[i] != goes[i] {
			t.Errorf("%s(%q): python3 gives %#v, the Go %#v", part, inputs[i], py[i], goes[i])
		}
	}
}

// goMergeTime is MergeTime's result as textDriver prints merge_time's.
func goMergeTime(s string) string {
	d, ok := MergeTime(s)
	if !ok {
		return "None"
	}
	_, offset := d.Zone()
	return fmt.Sprintf("%d %d %s", d.UnixMicro(), offset, LocalDay(d).Format(time.DateOnly))
}

// If any rule here drifted from report.py, or report.py's from it, a row below would differ: for
// example, PRKey keeping the repo's case, AgentName working per byte, MergeTime taking a time with no
// offset, or a change to report.py's pr_key alone.
func TestTextMatchesPython(t *testing.T) {
	saved := time.Local
	time.Local = time.FixedZone(localTZ, localOffset)
	t.Cleanup(func() { time.Local = saved })

	py := runPython(t, cases)
	t.Cleanup(func() {
		if t.Failed() {
			t.Logf("python3 is %s", py.Version)
		}
	})

	if py.AgentNameMax != AgentNameMax {
		t.Errorf("AGENT_NAME_MAX is %d in report.py and AgentNameMax %d", py.AgentNameMax, AgentNameMax)
	}
	if !slices.Equal(py.Phases, Phases()) {
		t.Errorf("PHASES is %q in report.py and Phases() %q", py.Phases, Phases())
	}

	var prKeys, names []string
	for _, s := range cases.PRKey {
		prKeys = append(prKeys, PRKey(s))
	}
	same(t, "PRKey", cases.PRKey, py.PRKey, prKeys)
	for _, s := range cases.AgentName {
		names = append(names, AgentName(s))
	}
	same(t, "AgentName", cases.AgentName, py.AgentName, names)

	for i, in := range cases.CutRecords {
		want := map[string]string{}
		for k, v := range py.CutRecords[i] {
			want[k] = "" // None, which CutRecords holds as ""
			if v != nil {
				want[k] = *v
			}
		}
		if got := CutRecords(in); !maps.Equal(got, want) {
			t.Errorf("CutRecords(%q): python3 gives %q, the Go %q", in, want, got)
		}
	}

	var results, steps, pySteps []string
	var escalates []bool
	for i, c := range cases.Escalate {
		results = append(results, c[0])
		escalates = append(escalates, EscalateBuild(c[0], c[1]))
		step := "None"
		if trigger, from, to, ok := StepUp(c[0]); ok {
			step = strconv.Quote(trigger) + " " + strconv.Quote(from) + " " + strconv.Quote(to)
		}
		steps = append(steps, step)
		pyStep := "None"
		if g := py.StepUp[i]; g != nil {
			pyStep = strconv.Quote(g[0]) + " " + strconv.Quote(g[1]) + " " + strconv.Quote(g[2])
		}
		pySteps = append(pySteps, pyStep)
	}
	same(t, "StepUp", results, pySteps, steps)
	same(t, "EscalateBuild", results, py.Escalate, escalates)

	var controls []string
	for _, s := range cases.Control {
		controls = append(controls, Control.ReplaceAllString(s, ""))
	}
	same(t, "Control", cases.Control, py.Control, controls)

	var times, pyTimes []string
	for i, s := range cases.MergeTime {
		times = append(times, goMergeTime(s))
		pyTime := "None"
		if p := py.MergeTime[i]; p != nil {
			pyTime = *p
		}
		pyTimes = append(pyTimes, pyTime)
	}
	same(t, "MergeTime", cases.MergeTime, pyTimes, times)
}

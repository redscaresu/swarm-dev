package report

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// reworkDriver runs report.py's rework rules over the cases on stdin (JSON, reworkInput's fields) and
// prints one line for each, as reworkLines prints the Go's. argv[1] is bin/lib. Each case sets TZ
// first, so its local days are its zone's; rework_of's stderr prints after its line.
const reworkDriver = `
import contextlib, io, json, os, sys, time
sys.path.insert(0, sys.argv[1])
import report
c = json.load(sys.stdin)
def zone(tz):
    os.environ["TZ"] = tz
    time.tzset()
w = sys.stdout.write
w("days %d\n" % report.REWORK_DAYS)
w("release %s\n" % " ".join(report.RELEASE_FILES))
for tz in c["zones"]:
    zone(tz)
    w("settled %s: %s\n" % (tz, report.rework_settled()))
for k in c["of"]:
    zone(k["tz"])
    merged = {m["key"]: (m["at"], m["text"], m["files"]) for m in k["merged"]}
    judged = None if k["judged"] is None else set(k["judged"])
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        got = report.rework_of(merged, k["findings"], judged)
    w("of %s: %s\n%s" % (k["name"], " ".join(sorted(got)), err.getvalue()))
for s in c["from"]:
    d = report.rework_from(s)
    w("from %s: %s\n" % (s, None if d is None else d.isoformat()))
for k in c["unknown"]:
    zone(k["tz"])
    w("unknown %s: %s\n" % (k["name"], report.rework_unknown(k["rows"], k["since"])))
`

// now is SWARM_DASH_NOW for both sides: 2026-10-20 12:00 UTC, so rework_settled is 2026-10-13 in UTC
// and UTC-7, and 2026-10-14 at UTC+14.
var now = time.Date(2026, time.October, 20, 12, 0, 0, 0, time.UTC)

// zone is a local zone both sides read: a POSIX TZ string, so python3 needs no zone files, and its
// offset east of UTC for Go's fixed zone.
type zone struct {
	TZ     string
	offset int
}

var (
	utc  = zone{"UTC0", 0}
	west = zone{"<-07>7", -7 * 60 * 60}   // Los Angeles in October: an evening merge is a UTC day later
	east = zone{"<+14>-14", 14 * 60 * 60} // a merge late in a UTC day is on the next local day
)

// local sets time.Local to z until the test ends.
func (z zone) local(t *testing.T) {
	saved := time.Local
	time.Local = time.FixedZone(z.TZ, z.offset)
	t.Cleanup(func() { time.Local = saved })
}

// merged is one merged PR as the driver reads it; files nil is Python's None.
type merged struct {
	Key   string   `json:"key"`
	At    string   `json:"at"`
	Text  string   `json:"text"`
	Files []string `json:"files"`
}

// ofCase is one rework_of call. judged nil is judged=None. want is the sorted keys and stderr both
// sides must give, so a case that stops testing what its name says fails too.
type ofCase struct {
	Name     string     `json:"name"`
	TZ       string     `json:"tz"`
	Merged   []merged   `json:"merged"`
	Findings [][]string `json:"findings"`
	Judged   []string   `json:"judged"`
	zone     zone
	want     string
	wantErr  string
}

// unknownCase is one rework_unknown call.
type unknownCase struct {
	Name  string              `json:"name"`
	TZ    string              `json:"tz"`
	Rows  []map[string]string `json:"rows"`
	Since string              `json:"since"`
	zone  zone
	want  bool
}

// fromCase is one rework_from call and the day both must give, "None" for none.
type fromCase struct{ since, want string }

// reworkInput is what the driver reads.
type reworkInput struct {
	Zones   []string      `json:"zones"`
	Of      []ofCase      `json:"of"`
	From    []string      `json:"from"`
	Unknown []unknownCase `json:"unknown"`
}

// The PRs most cases use: the one judged, merged 2026-10-01 10:00 UTC, and a later one in its repo.
const (
	pr1    = "o/r#1"
	pr2    = "o/r#2"
	merge1 = "2026-10-01T10:00:00Z"
)

// at1 is PR 1, merged at merge1 with no text.
var at1 = merged{Key: pr1, At: merge1}

// fixOf1 is PR 2 merged at t, saying it fixes #1, with files.
func fixOf1(t string, files ...string) merged {
	return merged{Key: pr2, At: t, Text: "Fixes #1", Files: files}
}

// escaped is a log-finding --reviewer escaped row on pr, dated day, as finding_rows gives it.
func escaped(day, pr string) []string {
	return []string{day, "missed", pr, "t", "escaped", "escaped"}
}

// skipped is rework_of's stderr line for n bad mergedAt values, the first on key.
func skipped(n int, key string) string {
	return "rework: skipped " + strconv.Itoa(n) + " merged PRs whose mergedAt does not parse, as " + key
}

// reworkTestPRs are tests/rework_test.sh's merged PRs with SWARM_DASH_NOW at now, and its PR #15,
// whose mergedAt does not parse.
var reworkTestPRs = []merged{
	{Key: "o/r#1", At: "2026-10-01T10:00:00Z", Text: "a\n"},
	{Key: "o/r#2", At: "2026-10-04T10:00:00Z", Text: "Fix a\nFixes #1."},
	{Key: "o/r#3", At: "2026-10-01T10:00:00Z", Text: "b\n"},
	{Key: "o/r#4", At: "2026-10-10T10:00:00Z", Text: "Fix https://github.com/o/r/pull/3\n"},
	{Key: "o/r#5", At: "2026-10-02T10:00:00Z", Text: "c\n"},
	{Key: "o/r#7", At: "2026-10-01T10:00:00Z", Text: "e\n"},
	{Key: "o/r#9", At: "2026-10-08T20:00:00Z", Text: "Hotfix for #7\n"},
	{Key: "o/r#10", At: "2026-10-18T12:00:00Z", Text: "f\n"},
	{Key: "o/r#11", At: "2026-10-02T01:00:00Z", Text: "g\n"},
	{Key: "o/r#13", At: "2026-10-18T12:00:00Z", Text: "h\n"},
	{Key: "o/r#14", At: "2026-10-19T12:00:00Z", Text: "Fix #13\n"},
	{Key: "o/r#15", At: "not-a-time", Text: "i\n"},
}

// reworkTestFindings are tests/rework_test.sh's findings.tsv rows.
var reworkTestFindings = [][]string{
	{"2026-10-01", "vacuous", "o/r#1", "t", "fixed", "codex"},
	{"2026-10-01", "nit", "o/r#1", "t", "declined", "code-review"},
	{"2026-10-01", "nit", "o/r#3", "t", "fixed", "lead"},
	{"2026-10-02", "vacuous", "o/r#5", "t", "fixed", "codex"},
	escaped("2026-10-05", "o/r#5"),
	escaped("2026-10-01", "o/r#11"),
}

// modelFit is tests/model_fit_test.sh's fixes call: PR 1 merged 2026-10-01 with no text and no files
// known, and the PR whose key is by merged a day later with text and files.
func modelFit(name, by, text string, files []string, want string) ofCase {
	return ofCase{Name: "model_fit: " + name, zone: utc, want: want, Merged: []merged{
		{Key: pr1, At: "2026-10-01T00:00:00Z"},
		{Key: by, At: "2026-10-02T00:00:00Z", Text: text, Files: files},
	}}
}

var release = []string{".claude-plugin/plugin.json"}

var ofCases = []ofCase{
	{Name: "a fix on day 7", zone: utc, want: pr1, Merged: []merged{at1, fixOf1("2026-10-08T10:00:00Z")}},
	{Name: "a fix on day 8", zone: utc, Merged: []merged{at1, fixOf1("2026-10-09T10:00:00Z")}},
	{Name: "a fix on day 7 late in the day, past 7x24 hours", zone: utc, want: pr1, Merged: []merged{at1, fixOf1("2026-10-08T23:59:59Z")}},
	{Name: "a fix 7 UTC days later, in UTC", zone: utc, want: pr1, Merged: []merged{{Key: pr1, At: "2026-10-01T09:00:00Z"}, fixOf1("2026-10-08T10:30:00Z")}},
	{Name: "a fix 7 UTC days later, 8 local days at UTC+14", zone: east, Merged: []merged{{Key: pr1, At: "2026-10-01T09:00:00Z"}, fixOf1("2026-10-08T10:30:00Z")}},
	{Name: "a fixer merged before the PR it names", zone: utc, Merged: []merged{at1, fixOf1("2026-09-30T10:00:00Z")}},
	{Name: "a fixer merged at the same instant", zone: utc, Merged: []merged{at1, fixOf1(merge1)}},
	{Name: "a fixer merged a microsecond later", zone: utc, want: pr1, Merged: []merged{at1, fixOf1("2026-10-01T10:00:00.000001Z")}},
	{Name: "a release PR fixes nothing", zone: utc, Merged: []merged{at1, fixOf1("2026-10-02T10:00:00Z", release...)}},
	{Name: "a PR changing plugin.json and more fixes", zone: utc, want: pr1, Merged: []merged{at1, fixOf1("2026-10-02T10:00:00Z", ".claude-plugin/plugin.json", "bin/x.sh")}},
	{Name: "a PR with no files known fixes", zone: utc, want: pr1, Merged: []merged{at1, fixOf1("2026-10-02T10:00:00Z")}},
	{Name: "a PR with no files changed fixes", zone: utc, want: pr1, Merged: []merged{at1, {Key: pr2, At: "2026-10-02T10:00:00Z", Text: "Fixes #1", Files: []string{}}}},
	{Name: "a PR never fixes itself", zone: utc, Merged: []merged{{Key: pr1, At: merge1, Text: "Fixes #1"}}},
	{Name: "a PR that does not say it fixes", zone: utc, Merged: []merged{at1, {Key: pr2, At: "2026-10-02T10:00:00Z", Text: "Stacked on #1"}}},
	{Name: "an escaped row on day -1", zone: utc, Merged: []merged{at1}, Findings: [][]string{escaped("2026-09-30", pr1)}},
	{Name: "an escaped row on day 0", zone: utc, want: pr1, Merged: []merged{at1}, Findings: [][]string{escaped("2026-10-01", pr1)}},
	{Name: "an escaped row on day 7", zone: utc, want: pr1, Merged: []merged{at1}, Findings: [][]string{escaped("2026-10-08", pr1)}},
	{Name: "an escaped row on day 8", zone: utc, Merged: []merged{at1}, Findings: [][]string{escaped("2026-10-09", pr1)}},
	{Name: "an escaped row naming the PR by its URL", zone: utc, want: pr1, Merged: []merged{at1}, Findings: [][]string{escaped("2026-10-02", "https://github.com/O/R/pull/1")}},
	{Name: "a fixed row is no escape", zone: utc, Merged: []merged{at1}, Findings: [][]string{{"2026-10-02", "missed", pr1, "t", "fixed", "codex"}}},
	{Name: "a row with no outcome", zone: utc, Merged: []merged{at1}, Findings: [][]string{{"2026-10-02", "missed", pr1, "t"}}},
	{Name: "bad finding dates, then a good one", zone: utc, want: pr1, Merged: []merged{at1}, Findings: [][]string{
		escaped("2026-13-01", pr1), escaped("2026-02-30", pr1), escaped("not-a-date", pr1), escaped("", pr1),
		escaped("2026-10-1", pr1), escaped("2026-10-0١", pr1), escaped("2026-10-02", pr1),
	}},
	{Name: "bad finding dates alone", zone: utc, Merged: []merged{at1}, Findings: [][]string{escaped("2026-13-01", pr1), escaped("garbage", pr1)}},
	{Name: "an escaped row on a PR not merged", zone: utc, Merged: []merged{at1}, Findings: [][]string{escaped("2026-10-02", "o/r#3")}},
	{Name: "a bad mergedAt, and one with no offset", zone: utc, wantErr: skipped(2, "o/r#5"), Merged: []merged{
		{Key: "o/r#5", At: "garbage"}, at1, {Key: "o/r#6", At: "2026-10-02T00:00:00", Text: "Fixes #1"},
	}, Findings: [][]string{escaped("2026-10-02", "o/r#5")}},
	{Name: "an empty mergedAt is left out unsaid", zone: utc, Merged: []merged{{Key: pr1}, fixOf1("2026-10-02T10:00:00Z")}, Findings: [][]string{escaped("2026-10-02", pr1)}},
	{Name: "a key given twice keeps its first place and last value", zone: utc, wantErr: skipped(2, "o/r#5"), Merged: []merged{
		{Key: "o/r#5", At: "bad"}, {Key: "o/r#6", At: "bad"}, {Key: "o/r#5", At: "still bad"}, {Key: pr1, At: "bad"}, at1,
	}},
	{Name: "judged not given", zone: utc, want: "o/r#1 o/r#3", Merged: []merged{
		at1, fixOf1("2026-10-02T10:00:00Z"), {Key: "o/r#3", At: merge1},
	}, Findings: [][]string{escaped("2026-10-02", "o/r#3")}},
	{Name: "judged given", zone: utc, want: pr1, Judged: []string{pr1, "o/r#9"}, Merged: []merged{
		at1, fixOf1("2026-10-02T10:00:00Z"), {Key: "o/r#3", At: merge1},
	}, Findings: [][]string{escaped("2026-10-02", "o/r#3")}},
	{Name: "judged given empty", zone: utc, Judged: []string{}, Merged: []merged{at1, fixOf1("2026-10-02T10:00:00Z")}, Findings: [][]string{escaped("2026-10-02", pr1)}},
	{Name: "an unjudged PR still fixes", zone: utc, want: pr1, Judged: []string{pr1}, Merged: []merged{at1, fixOf1("2026-10-02T10:00:00Z")}},
	{Name: "rework_test's fixture in UTC", zone: utc, want: "o/r#1 o/r#13 o/r#5 o/r#7", wantErr: skipped(1, "o/r#15"), Merged: reworkTestPRs, Findings: reworkTestFindings},
	{Name: "rework_test's fixture in UTC-7", zone: west, want: "o/r#1 o/r#11 o/r#13 o/r#5 o/r#7", wantErr: skipped(1, "o/r#15"), Merged: reworkTestPRs, Findings: reworkTestFindings},
	modelFit("a fix", pr2, "Fix #1", nil, pr1),
	modelFit("a fix after a merge-after sentence", pr2, "Merge after #3. Fixes #1", nil, pr1),
	modelFit("a release PR", pr2, "Release: fixes #1", release, ""),
	modelFit("a PR changing bin/x.sh", pr2, "Fixes #1", []string{"bin/x.sh"}, pr1),
	modelFit("a bare #N from another repo", "b/two#2", "Fix #1", nil, ""),
	modelFit("owner/repo#N from another repo", "b/two#2", "Fix o/r#1", nil, pr1),
	modelFit("owner/repo#N with no left boundary", "b/two#2", "Fix foo/r#1", nil, ""),
	{Name: "model_fit: a mergedAt that does not parse, or has no offset", zone: utc, wantErr: skipped(2, pr1), Merged: []merged{
		{Key: pr1, At: "garbage"}, {Key: pr2, At: "2026-10-02T00:00:00", Text: "Fix #1"}, {Key: "o/r#3", At: "2026-10-03T00:00:00Z", Text: "Fix #2"},
	}},
}

var fromCases = []fromCase{
	{"2026-10-09", "2026-10-02"},
	{"2026-03-03", "2026-02-24"},
	{"0001-01-08", "0001-01-01"},
	{"0001-01-07", "None"},
	{"9999-12-31", "9999-12-24"},
	{"0000-00-00", "None"},
	{"", "None"},
	{"2026-02-30", "None"},
	{"2026-10-9", "None"},
	{"not-a-date", "None"},
	{"2026-10-0٩", "None"},
}

// row is an outcomes row with a pr, a merged_at and a rework cell.
func row(pr, mergedAt, rework string) map[string]string {
	return map[string]string{"pr": pr, "merged_at": mergedAt, "rework": rework}
}

// The days around rework_settled in UTC, 2026-10-13: a day before it, and the day itself.
const (
	beforeSettled = "2026-10-12T10:00:00Z"
	onSettled     = "2026-10-13T10:00:00Z"
)

var unknownCases = []unknownCase{
	{Name: "an empty cell before settled", zone: utc, want: true, Rows: []map[string]string{row(pr1, beforeSettled, "")}},
	{Name: "a 0 before settled", zone: utc, Rows: []map[string]string{row(pr1, beforeSettled, "0")}},
	{Name: "an empty cell on the settled day", zone: utc, Rows: []map[string]string{row(pr1, onSettled, "")}},
	{Name: "an empty cell after settled", zone: utc, Rows: []map[string]string{row(pr1, "2026-10-15T10:00:00Z", "")}},
	{Name: "an empty cell a UTC day before settled, local -7", zone: west, want: true, Rows: []map[string]string{row(pr1, "2026-10-13T03:00:00Z", "")}},
	{Name: "an empty cell a UTC day before settled, in UTC", zone: utc, Rows: []map[string]string{row(pr1, "2026-10-13T03:00:00Z", "")}},
	{Name: "an empty cell on the UTC settled day, a day before it at UTC+14", zone: east, want: true, Rows: []map[string]string{row(pr1, "2026-10-13T09:00:00Z", "")}},
	{Name: "the latest build has the cell", zone: utc, Rows: []map[string]string{row(pr1, beforeSettled, ""), row("https://github.com/o/r/pull/1", beforeSettled, "1")}},
	{Name: "the latest build has an empty cell", zone: utc, want: true, Rows: []map[string]string{row(pr1, beforeSettled, "1"), row(pr1, beforeSettled, "")}},
	{Name: "since 2026-10-09 leaves out a merge on 2026-10-01", zone: utc, Since: "2026-10-09", Rows: []map[string]string{row(pr1, merge1, "")}},
	{Name: "since 2026-10-09 takes a merge on 2026-10-02", zone: utc, want: true, Since: "2026-10-09", Rows: []map[string]string{row(pr1, "2026-10-02T00:00:00Z", "")}},
	{Name: "since 0000-00-00 takes every merge", zone: utc, want: true, Since: "0000-00-00", Rows: []map[string]string{row(pr1, merge1, "")}},
	{Name: "a bad since takes every merge", zone: utc, want: true, Since: "nonsense", Rows: []map[string]string{row(pr1, merge1, "")}},
	{Name: "no rework column", zone: utc, Rows: []map[string]string{{"pr": pr1, "merged_at": beforeSettled}}},
	{Name: "no pr", zone: utc, Rows: []map[string]string{row("", beforeSettled, ""), {"merged_at": beforeSettled, "rework": ""}}},
	{Name: "a merged_at that does not parse", zone: utc, Rows: []map[string]string{row(pr1, "not-a-time", ""), {"pr": pr2, "rework": ""}}},
	{Name: "one unknown among known", zone: utc, want: true, Rows: []map[string]string{row(pr1, beforeSettled, "1"), row(pr2, merge1, ""), row("o/r#3", onSettled, "")}},
	{Name: "no rows", zone: utc},
}

// zones are the zones rework_settled is printed in, and the day each must give.
var zones = []struct {
	z    zone
	want string
}{{utc, "2026-10-13"}, {west, "2026-10-13"}, {east, "2026-10-14"}}

// runRework runs reworkDriver over in under the python3 on PATH, with python3 -I so no PYTHONPATH or
// user site reaches it, and SWARM_DASH_NOW from the test's environment.
func runRework(t *testing.T, in reworkInput) string {
	t.Helper()
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	stdin, err := json.Marshal(in)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonSeconds*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-c", reworkDriver, lib)
	cmd.Stdin = bytes.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 -I over report.py's rework rules: %v\n%s", err, stderr.String())
	}
	return string(out)
}

// toMerged is a case's PRs as ReworkOf takes them.
func toMerged(ms []merged) []MergedPR {
	var out []MergedPR
	for _, m := range ms {
		out = append(out, MergedPR{Key: m.Key, MergedAt: m.At, Text: m.Text, Files: m.Files})
	}
	return out
}

// toJudge is a case's judged as ReworkOf takes it.
func toJudge(judged []string) Judge {
	if judged == nil {
		return Judge{Every: true}
	}
	keys := map[string]bool{}
	for _, k := range judged {
		keys[k] = true
	}
	return Judge{Keys: keys}
}

// sortedKeys is a set's keys, sorted and joined by spaces as the driver joins them.
func sortedKeys(set map[string]bool) string {
	var keys []string
	for k := range set {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	return strings.Join(keys, " ")
}

// errLine is rework_of's stderr as Python prints it: the line and a newline, or nothing.
func errLine(line string) string {
	if line == "" {
		return ""
	}
	return line + "\n"
}

// pyBool is a bool as Python prints it.
func pyBool(b bool) string {
	return map[bool]string{true: "True", false: "False"}[b]
}

// reworkLines is what the Go gives for in, as reworkDriver prints report.py's, and fails each case
// whose result is not its want.
func reworkLines(t *testing.T, in reworkInput) string {
	t.Helper()
	var b strings.Builder
	fmt.Fprintf(&b, "days %d\nrelease %s\n", ReworkDays, strings.Join(ReleaseFiles(), " "))
	for _, z := range zones {
		z.z.local(t)
		settled, err := ReworkSettled()
		if err != nil {
			t.Fatal(err)
		}
		if settled != z.want {
			t.Errorf("ReworkSettled at %s: %s, want %s", z.z.TZ, settled, z.want)
		}
		fmt.Fprintf(&b, "settled %s: %s\n", z.z.TZ, settled)
	}
	for _, c := range ofCases {
		c.zone.local(t)
		got, line := ReworkOf(toMerged(c.Merged), c.Findings, toJudge(c.Judged))
		if sortedKeys(got) != c.want || line != c.wantErr {
			t.Errorf("ReworkOf: %s: %q and %q, want %q and %q", c.Name, sortedKeys(got), line, c.want, c.wantErr)
		}
		fmt.Fprintf(&b, "of %s: %s\n%s", c.Name, sortedKeys(got), errLine(line))
	}
	for _, c := range fromCases {
		got := "None"
		if d, ok := ReworkFrom(c.since); ok {
			got = d.Format(time.DateOnly)
		}
		if got != c.want {
			t.Errorf("ReworkFrom(%q): %s, want %s", c.since, got, c.want)
		}
		fmt.Fprintf(&b, "from %s: %s\n", c.since, got)
	}
	for _, c := range unknownCases {
		c.zone.local(t)
		got, err := ReworkUnknown(c.Rows, c.Since)
		if err != nil {
			t.Fatal(err)
		}
		if got != c.want {
			t.Errorf("ReworkUnknown: %s: %v, want %v", c.Name, got, c.want)
		}
		fmt.Fprintf(&b, "unknown %s: %s\n", c.Name, pyBool(got))
	}
	return b.String()
}

// If any rework rule here drifted from report.py, or report.py's from it, a line would differ: for
// example ReworkOf counting a fix on day 8, letting a release PR fix, or reading days in UTC, or
// report.py's rework_of alone counting an escaped row on day -1.
func TestReworkMatchesPython(t *testing.T) {
	t.Setenv("SWARM_DASH_NOW", strconv.FormatInt(now.Unix(), 10))
	in := reworkInput{From: []string{}}
	for _, z := range zones {
		in.Zones = append(in.Zones, z.z.TZ)
	}
	for _, c := range ofCases {
		c.TZ = c.zone.TZ
		if c.Findings == nil {
			c.Findings = [][]string{}
		}
		in.Of = append(in.Of, c)
	}
	for _, c := range fromCases {
		in.From = append(in.From, c.since)
	}
	for _, c := range unknownCases {
		c.TZ = c.zone.TZ
		if c.Rows == nil {
			c.Rows = []map[string]string{}
		}
		in.Unknown = append(in.Unknown, c)
	}
	py := runRework(t, in)
	goes := reworkLines(t, in)
	if py == goes {
		t.Logf("%d rework_of, %d rework_from and %d rework_unknown cases: report.py and the Go print the same",
			len(ofCases), len(fromCases), len(unknownCases))
		return
	}
	pyLines, goLines := strings.Split(py, "\n"), strings.Split(goes, "\n")
	for i := 0; i < max(len(pyLines), len(goLines)); i++ {
		p, g := "", ""
		if i < len(pyLines) {
			p = pyLines[i]
		}
		if i < len(goLines) {
			g = goLines[i]
		}
		if p != g {
			t.Errorf("line %d: python3 %q, the Go %q", i+1, p, g)
		}
	}
	t.Errorf("report.py and the Go differ:\npython3:\n%sgo:\n%s", py, goes)
}

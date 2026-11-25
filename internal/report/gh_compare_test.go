package report

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/gh"
	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/pyjson"
)

// stubDirVar names the folder of the case the stub gh answers: its answers, its count and its calls.
const stubDirVar = "GH_STUB_DIR"

// sleepScale is the scale both sides' retry sleeps run at, so a case that retries takes well under a
// second on each side.
const (
	scaleVar   = "SWARM_SLEEP_SCALE"
	sleepScale = "0.01"
)

// shortBound is the bound of the case whose gh outlives it, in seconds: long enough for the stub to
// start and log its call on a loaded machine, where one process start can take two seconds.
const shortBound = 5

// ghPythonSeconds bounds the python3 run. Its cases start a few hundred processes, which can take
// half a minute on a slow machine.
const ghPythonSeconds = 300

// stubGh answers its nth call in $GH_STUB_DIR with the script rN, or the last one once n passes max.
// It first logs the call's arguments, each in brackets, as one line of calls, with shell builtins
// only, so the log is written before any program it starts could let a short bound pass.
const stubGh = `#!/bin/sh
d=$` + stubDirVar + `
for a in "$@"; do printf '[%s]' "$a"; done >> "$d/calls"
echo >> "$d/calls"
n=$(cat "$d/count" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$d/count"
max=$(cat "$d/max")
[ "$n" -le "$max" ] || n=$max
exec /bin/sh "$d/r$n"
`

// ghDriver runs report.py's gh and search_merged over the cases on stdin (ghCases' fields) and prints
// ghResults as JSON. argv[1] is bin/lib. Each call case starts with ERROR and LIMIT empty, and its
// steps share them, as one flow run's calls do.
const ghDriver = `
import json, os, sys
sys.path.insert(0, sys.argv[1])
import report
c = json.load(sys.stdin)
calls = []
for case in c["calls"]:
    os.environ["` + stubDirVar + `"] = case["dir"]
    report.ERROR[0], report.LIMIT[0] = "", ""
    steps = []
    for st in case["steps"]:
        r = report.gh(*st["args"], seconds=st["seconds"], parse=str if st["text"] else json.loads)
        steps.append({"result": json.dumps(r), "error": report.ERROR[0], "limit": report.LIMIT[0]})
    calls.append(steps)
searches = []
for case in c["searches"]:
    os.environ["` + stubDirVar + `"] = case["dir"]
    searches.append(json.dumps(report.search_merged(*case["search"])))
json.dump({
    "version": sys.version.split()[0],
    "gh_seconds": report.GH_SECONDS,
    "gh_limit": report.GH_LIMIT,
    "passes": [report.PASSES.search(p) is not None for p in c["probes"]],
    "spent": [report.SPENT.search(p) is not None for p in c["probes"]],
    "calls": calls,
    "searches": searches,
}, sys.stdout)
`

// step is one Call, which the driver makes as report.py's gh(*args, seconds=seconds, parse=...).
type step struct {
	Args    []string `json:"args"`
	Seconds int      `json:"seconds"`
	Text    bool     `json:"text"` // parse=str, else json.loads
}

// callCase is a run of gh calls against one scripted gh: answers[n] is the script its nth call runs,
// the last one for every call after.
type callCase struct {
	name    string
	answers []string
	Steps   []step `json:"steps"`
	Dir     string `json:"dir"`
}

// searchCase is one search_merged against one scripted gh.
type searchCase struct {
	name    string
	answers []string
	Search  [3]string `json:"search"` // repo, lo, hi
	Dir     string    `json:"dir"`
}

type ghCases struct {
	Calls    []*callCase   `json:"calls"`
	Searches []*searchCase `json:"searches"`
	Probes   []string      `json:"probes"`
}

// stepResult is one Call's answer as json.dumps writes it, and Error and Limit after it.
type stepResult struct {
	Result string `json:"result"`
	Error  string `json:"error"`
	Limit  string `json:"limit"`
}

type ghResults struct {
	Version   string         `json:"version"` // python3's, for a failure's log
	GHSeconds int            `json:"gh_seconds"`
	GHLimit   int            `json:"gh_limit"`
	Passes    []bool         `json:"passes"`
	Spent     []bool         `json:"spent"`
	Calls     [][]stepResult `json:"calls"`
	Searches  []string       `json:"searches"`
}

// The scripts a stub gh answer runs. \377 and \376 are bytes that are not UTF-8.
const (
	reset    = `printf 'read tcp 1.2.3.4:5->6.7.8.9:443: read: connection reset by peer\n' >&2; exit 1`
	badGate  = `printf 'HTTP 502: Bad Gateway (https://api.github.com/x)\n' >&2; exit 1`
	answerOK = `printf '{"ok": 1}'`
	notFound = `printf 'first line\n\n  HTTP 404: Not Found (https://api.github.com/repos/o/r)  \n' >&2; exit 1`
	spentMsg = `printf 'gh: API rate limit exceeded for user ID 1. If you reach out, include the ID.\n' >&2; exit 1`
	prList   = `printf '[{"url": "https://github.com/o/r/pull/1", "mergedAt": "2026-11-01T00:00:00Z", "title": "T\\u00e9", "body": null, "files": [{"path": "a"}]}]\r\n'`
)

// api is the args of a plain gh api call.
func api(path string) step { return step{Args: []string{"api", path}, Seconds: GHSeconds} }

var ghCaseList = ghCases{
	Calls: []*callCase{
		{name: "JSON, key order kept", answers: []string{`printf '{"b": 1, "a": [true, null, "x\\u00e9", -2, 12345678901234567890]}\r\n'`},
			Steps: []step{api("repos/o/r/pulls/1")}},
		{name: "the call text stops at --json", answers: []string{`printf '[]'`},
			Steps: []step{{Args: []string{"run", "list", "-R", "o/r", "--json", "a,b", "--limit", "5"}, Seconds: GHSeconds}}},
		{name: "not JSON", answers: []string{`printf 'hello'`}, Steps: []step{api("x")}},
		{name: "JSON null", answers: []string{`printf 'null'`}, Steps: []step{api("x")}},
		{name: "empty answer", answers: []string{`:`}, Steps: []step{api("x")}},
		{name: "JSON with a raw CR in a string", answers: []string{`printf '["a\rb"]'`}, Steps: []step{api("x")}},
		{name: "bad UTF-8 as JSON", answers: []string{`printf '{"a": "\377"}'`}, Steps: []step{api("x")}},
		{name: "bad UTF-8 as text", answers: []string{`printf 'a\377b\r\nc\rd\n'`},
			Steps: []step{{Args: []string{"run", "view", "1", "--log-failed"}, Seconds: GHSeconds, Text: true}}},
		{name: "text keeps nothing but LF", answers: []string{`printf 'one\r\ntwo\rthree\n\r\n'`},
			Steps: []step{{Args: []string{"run", "view", "1"}, Seconds: GHSeconds, Text: true}}},
		{name: "exit 1 with stderr, a 404", answers: []string{notFound}, Steps: []step{api("repos/o/r")}},
		{name: "exit 3, no stderr", answers: []string{`exit 3`}, Steps: []step{api("x")}},
		{name: "stderr of only spaces", answers: []string{`printf ' \t\n\n' >&2; exit 4`}, Steps: []step{api("x")}},
		{name: "bad UTF-8 on stderr", answers: []string{`printf 'bad \376 byte\n' >&2; exit 1`}, Steps: []step{api("x")}},
		{name: "Python's other line breaks", answers: []string{`printf 'one\vtwo\034 three \302\205' >&2; exit 2`}, Steps: []step{api("x")}},
		{name: "a TERM death", answers: []string{`kill -TERM $$`}, Steps: []step{api("x")}},
		{name: "a 502 then JSON", answers: []string{badGate, answerOK}, Steps: []step{api("x")}},
		{name: "a reset three times", answers: []string{reset}, Steps: []step{api("x"), api("y")}},
		{name: "a dotless-i timeout then JSON", answers: []string{`printf 'net/http: TLS handshaKe t\304\261meout\n' >&2; exit 1`, answerOK},
			Steps: []step{api("x")}},
		{name: "a 5xx in the call's own words", answers: []string{`exit 1`, answerOK}, Steps: []step{api("HTTP 503")}},
		{name: "a secondary rate limit", answers: []string{`printf 'You have exceeded a secondary rate limit\n' >&2; exit 1`},
			Steps: []step{api("x"), api("y")}},
		{name: "the rate limit then another call", answers: []string{spentMsg, answerOK},
			Steps: []step{api("x"), api("y"), {Args: []string{"run", "view", "--json", "a"}, Seconds: GHSeconds, Text: true}}},
		{name: "the limit after a 5xx", answers: []string{badGate, `printf 'API rate limit already exceeded\n' >&2; exit 1`, answerOK},
			Steps: []step{api("x"), api("y")}},
		{name: "a sleep past a short bound", answers: []string{`exec sleep 30`},
			Steps: []step{{Args: []string{"api", "slow"}, Seconds: shortBound}}},
	},
	Searches: []*searchCase{
		{name: "a list", answers: []string{prList}},
		{name: "an empty list", answers: []string{`printf '[]'`}},
		{name: "an object", answers: []string{`printf '{"a": 1}'`}},
		{name: "not JSON", answers: []string{`printf 'nope'`}},
		{name: "exit 1", answers: []string{`printf '[]'; exit 1`}},
		{name: "bad UTF-8 on stdout", answers: []string{`printf '["\377"]'`}},
		{name: "bad UTF-8 on stderr, exit 0", answers: []string{`printf '[]'; printf 'w\377\n' >&2`}},
		{name: "a 502, not tried again", answers: []string{badGate, `printf '[]'`}},
	},
	Probes: []string{
		"connection reset", "Connection Reset by peer", "connectİon reset", "connectıon reset", "connection reſet",
		"unexpected EOF", "unexpected eof", "i/o timeout", "I/O TIMEOUT", "ı/o tımeout", "TLS handshake timeout",
		"TLS handshaKe timeout", "HTTP 500", "http 599", "HTTP 5٠٠", "HTTP 5x0", "HTTP 50", "HTTP 404", "HTTP 5000",
		"connection refused", "API rate limit exceeded", "API rate limit already exceeded", "api rate limit exceeded",
		"API rate limit  exceeded", "secondary rate limit", "",
	},
}

// ghStubPath writes stubGh into a new folder and gives PATH with that folder first.
func ghStubPath(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(stubGh), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir + string(os.PathListSeparator) + os.Getenv("PATH")
}

// caseDir makes a folder holding a case's answers, r1 to rN, and N in max.
func caseDir(t *testing.T, answers []string) string {
	t.Helper()
	dir := t.TempDir()
	for i, a := range answers {
		if err := os.WriteFile(filepath.Join(dir, "r"+strconv.Itoa(i+1)), []byte(a+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "max"), []byte(strconv.Itoa(len(answers))+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

// callsLog is the calls a case's stub logged, one line a call.
func callsLog(t *testing.T, dir string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, "calls"))
	if errors.Is(err, os.ErrNotExist) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// runGhDriver runs ghDriver over cases under python3 -I, with path as PATH.
func runGhDriver(t *testing.T, cases ghCases, path string) ghResults {
	t.Helper()
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	stdin, err := json.Marshal(cases)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), ghPythonSeconds*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-c", ghDriver, lib)
	cmd.Env = append(os.Environ(), "PATH="+path, scaleVar+"="+sleepScale)
	cmd.Stdin = bytes.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 -I over report.py's gh: %v\n%s", err, stderr.String())
	}
	var got ghResults
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatalf("python3's output is not the results: %v\n%s", err, out)
	}
	return got
}

// dumps is v as json.dumps writes it, the way the driver prints report.py's answers.
func dumps(t *testing.T, v any) string {
	t.Helper()
	b, err := pyjson.Encode(v)
	if err != nil {
		t.Fatalf("encoding %#v: %v", v, err)
	}
	return string(b)
}

// If GH or SearchMerged drifted from report.py's gh and search_merged, or theirs from it, a row here
// would differ: for example GH trying a 404 again, calling gh once the hourly limit is spent, or
// reading text without turning CR into LF, or report.py's gh alone keeping CR. Each case runs against
// its own copy of one scripted gh, once for report.py and once for the Go, and the answers, Error,
// Limit and the calls the stub logged must match byte for byte.
func TestGHMatchesPython(t *testing.T) {
	path := ghStubPath(t)
	py, goes := ghCaseList, ghCases{Probes: ghCaseList.Probes}
	py.Calls, py.Searches = nil, nil
	for _, c := range ghCaseList.Calls {
		pc, gc := *c, *c
		pc.Dir, gc.Dir = caseDir(t, c.answers), caseDir(t, c.answers)
		py.Calls, goes.Calls = append(py.Calls, &pc), append(goes.Calls, &gc)
	}
	for _, c := range ghCaseList.Searches {
		pc, gc := *c, *c
		pc.Search = [3]string{"Owner/Repo", "2026-11-01", "2026-11-24"}
		gc.Search = pc.Search
		pc.Dir, gc.Dir = caseDir(t, c.answers), caseDir(t, c.answers)
		py.Searches, goes.Searches = append(py.Searches, &pc), append(goes.Searches, &gc)
	}

	got := runGhDriver(t, py, path)
	t.Cleanup(func() {
		if t.Failed() {
			t.Logf("python3 is %s", got.Version)
		}
	})
	if got.GHSeconds != GHSeconds || got.GHLimit != GHLimit {
		t.Errorf("GH_SECONDS, GH_LIMIT are %d, %d in report.py and GHSeconds, GHLimit %d, %d", got.GHSeconds, got.GHLimit, GHSeconds, GHLimit)
	}
	for i, p := range ghCaseList.Probes {
		if Passes.MatchString(p) != got.Passes[i] || Spent.MatchString(p) != got.Spent[i] {
			t.Errorf("probe %q: PASSES, SPENT search %v, %v in report.py and Passes, Spent match %v, %v",
				p, got.Passes[i], got.Spent[i], Passes.MatchString(p), Spent.MatchString(p))
		}
	}

	t.Setenv("PATH", path)
	t.Setenv(scaleVar, sleepScale)
	for i, c := range goes.Calls {
		t.Setenv(stubDirVar, c.Dir)
		g := &GH{Host: gh.Host{}}
		for j, s := range c.Steps {
			parse := JSON
			if s.Text {
				parse = Text
			}
			want, have := got.Calls[i][j], stepResult{dumps(t, g.Call(s.Seconds, parse, s.Args...)), g.Error, g.Limit}
			if have != want {
				t.Errorf("%s, call %d (%q): python3 gives %#v, the Go %#v", c.name, j+1, s.Args, want, have)
			}
		}
		if pyCalls, goCalls := callsLog(t, py.Calls[i].Dir), callsLog(t, c.Dir); pyCalls != goCalls {
			t.Errorf("%s: report.py's gh called\n%s\nand the Go\n%s", c.name, pyCalls, goCalls)
		}
	}
	for i, c := range goes.Searches {
		t.Setenv(stubDirVar, c.Dir)
		prs, ok := (&GH{Host: gh.Host{}}).SearchMerged(c.Search[0], c.Search[1], c.Search[2])
		have := "null"
		if ok {
			have = dumps(t, prs)
		}
		if have != got.Searches[i] {
			t.Errorf("search %s: python3 gives %s, the Go %s", c.name, got.Searches[i], have)
		}
		if pyCalls, goCalls := callsLog(t, py.Searches[i].Dir), callsLog(t, c.Dir); pyCalls != goCalls {
			t.Errorf("search %s: search_merged called\n%s\nand the Go\n%s", c.name, pyCalls, goCalls)
		}
	}
}

// fixedHost answers every Run with result.
type fixedHost struct{ result iface.GhResult }

func (f fixedHost) Run(context.Context, ...string) iface.GhResult { return f.result }

// report.py's gh raises FileNotFoundError for a gh it cannot start, which no python3 run can compare,
// and search_merged gives None for it and for a bound that passed. If Call tries a gh that cannot start
// again or leaves Error stale, or SearchMerged passes either on as a list, this goes red.
func TestGHFailuresPythonCannotCompare(t *testing.T) {
	noGh := fixedHost{iface.GhResult{Exit: -1, NoStart: exec.ErrNotFound}}
	g := &GH{Host: noGh, Error: "stale"}
	if v := g.Call(GHSeconds, JSON, "api", "x"); v != nil || g.Error != "gh api x: "+exec.ErrNotFound.Error() || g.Limit != "" {
		t.Errorf("Call with no gh = %#v, Error %q, Limit %q; want nil, %q, \"\"", v, g.Error, g.Limit, "gh api x: "+exec.ErrNotFound.Error())
	}
	for _, h := range []fixedHost{noGh, {iface.GhResult{Exit: -1, CutShort: true, Stdout: []byte("[]")}}} {
		if prs, ok := (&GH{Host: h}).SearchMerged("o/r", "a", "b"); ok || prs != nil {
			t.Errorf("SearchMerged on %+v = %v, %v; want nil, false", h.result, prs, ok)
		}
	}
}

package eventsoutcome

import (
	"bytes"
	"context"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"
)

// pythonTimeout bounds the one python3 run of the comparison test.
const pythonTimeout = time.Minute

// libDir is bin/lib, where events_outcome.py lives, relative to this package's directory.
const libDir = "../../bin/lib"

// pyReader prints what events_outcome.py reads from each row of the JSON list on stdin, in the
// format put describes. Its first line is SEP alone. argv[1] is bin/lib, put first on sys.path.
const pyReader = `import json, sys
sys.path.insert(0, sys.argv[1])
import events_outcome as eo

def put(s):
    b = s.encode("utf-8")
    return str(len(b)).encode() + b":" + b

lines = [put(eo.SEP)]
for row in json.loads(sys.stdin.buffer.read()):
    f = eo.fields(row)
    lines.append(b" ".join([put(eo.outcome(row))] + [put(x) for k in sorted(f) for x in (k, f[k])]))
sys.stdout.buffer.write(b"".join(line + b"\n" for line in lines))
`

// put is one string as both sides print it: its length in UTF-8 bytes, a colon, then the bytes, so
// no value can pass for a separator.
func put(s string) string { return strconv.Itoa(len(s)) + ":" + s }

// goReader prints what the Go reads from each row, in the format pyReader prints.
func goReader(rows [][]string) string {
	lines := []string{put(Sep)}
	for _, row := range rows {
		f := Fields(row)
		keys := make([]string, 0, len(f))
		for k := range f {
			keys = append(keys, k)
		}
		sort.Strings(keys) // byte order, which is Python's code point order for valid UTF-8
		parts := []string{put(Outcome(row))}
		for _, k := range keys {
			parts = append(parts, put(k), put(f[k]))
		}
		lines = append(lines, strings.Join(parts, " "))
	}
	return strings.Join(lines, "\n") + "\n"
}

// row is an events.tsv row of five columns whose outcome column is col.
func row(col string) []string { return []string{"2026-10-01T00:00:00Z", "x", "t", "w:me", col} }

// compareRows are the rows both sides read.
var compareRows = [][]string{
	// What tests/events_test.sh's tail cases write (as append_event wrote them) and read back with
	// read_py (:326), malformed cases among them.
	row("ok (round 2) ~~ round=2 verdict=pass"),
	row("die: no story"),
	row("a b ~~ k=v"),
	row("a b"),
	row("a b  c ~~ n=1 m=two"),
	row("ok ~~ good=1"),
	row("ok"),
	row("die: foo ~~ round=2"),
	row("die: foo"),
	row("ok (round 2)"),
	row("failed: key=value x=1"),
	row(`{"result":{"agent":{"agent_status":"working","note":"a=b c"}}}`),
	row("base-merged abc from def ~~ round=3 why=x=y"),
	// The ~~ k=v tail tests/events_tail_flow_test.sh writes on every row.
	row("merged ~~ k=v"),
	row("conduct-start ~~ k=v"),
	// The first Sep starts the tail; Sep at the start; several Seps.
	row("a ~~ b ~~ k=v"),
	row(" ~~ k=v"),
	row(" ~~ "),
	row("x ~~ a=1 ~~ b=2 ~~ c=3"),
	row("x ~~  ~~ a=1"),
	row("ok  ~~  k=v"),
	row("ok ~~~ k=v"),
	row("ok ~~"),
	row("ok ~~ "),
	// = inside a value, repeated keys, empty values and keys, a field with no =, double spaces.
	row("ok ~~ why=x=y=z eq=="),
	row("ok ~~ k=1 k=2 j=a k=3"),
	row("ok ~~ k=1 k="),
	row("ok ~~ empty= =v = bare k=v"),
	row("ok ~~ a=1  b=2   c=3"),
	// Short and long rows: no tab, 4 columns or fewer, more than 5.
	{"no tab here ~~ k=v"},
	{},
	{"2026-10-01T00:00:00Z", "x", "t", "w:me"},
	{"2026-10-01T00:00:00Z", "x", "t", "w:me", ""},
	{"2026-10-01T00:00:00Z", "x", "t", "w:me", "ok ~~ k=v", "extra ~~ j=w"},
	// Non-ASCII in the outcome, keys and values.
	row("café ~~ naïve=ü ключ=значение"),
	row("日本 ~~ 鍵=値 鍵=後 🙂=☃"),
}

// TestCompareWithPython runs events_outcome.py and the Go over the same rows and compares what they
// print byte for byte. It fails, rather than skips, when python3 cannot run.
func TestCompareWithPython(t *testing.T) {
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Fatalf("the comparison test needs python3 on PATH: %v", err)
	}
	lib, err := filepath.Abs(libDir)
	if err != nil {
		t.Fatalf("bin/lib: %v", err)
	}
	input, err := json.Marshal(compareRows)
	if err != nil {
		t.Fatalf("the rows as JSON: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, python, "-I", "-c", pyReader, lib)
	cmd.Stdin = bytes.NewReader(input)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	got, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 events_outcome: %v\n%s", err, stderr.String())
	}
	py, want := strings.Split(string(got), "\n"), strings.Split(goReader(compareRows), "\n")
	if len(py) != len(want) {
		t.Fatalf("python3 printed %d lines, the Go %d:\npython3:\n%s\nGo:\n%s", len(py), len(want), got, goReader(compareRows))
	}
	for i := range py {
		if py[i] == want[i] {
			continue
		}
		if i == 0 {
			t.Errorf("SEP: python3 %q, Go %q", py[i], want[i])
			continue
		}
		t.Errorf("row %d %q:\npython3 %s\nGo      %s", i-1, compareRows[i-1], py[i], want[i])
	}
}

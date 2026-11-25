package touchesrows

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
	"github.com/redscaresu/swarm-dev/internal/eventsoutcome"
)

// filesDriver runs each case on stdin through touches_rows.py's file readers and prints its result
// as one line of json.dumps(sort_keys=True); a reader that raises prints "error".
const filesDriver = `
import calendar, json, sys, time
sys.path.insert(0, sys.argv[1])
import touches_rows as t

def run(c):
    op = c["op"]
    if op == "front":
        return t.front(c["path"], c["state"])
    if op == "entries":
        return [list(e) for e in t.entries(c["fm"] or {}, c["project"], c["repos"])]
    if op == "front_entries":
        return [list(e) for e in t.entries(t.front(c["path"], c["state"]), c["project"], c["repos"])]
    if op == "events":
        return sorted([k[0], k[1], v] for k, v in t.ok_events(c["path"]).items())
    if op == "time":
        try:
            return calendar.timegm(time.strptime(c["text"], "%Y-%m-%dT%H:%M:%SZ"))
        except ValueError:
            return None
    raise SystemExit("unknown op " + op)

for c in json.load(sys.stdin):
    try:
        out = run(c)
    except OSError:
        out = "error"
    print(json.dumps(out, sort_keys=True))
`

// fcase is one file-reader input both sides run. Op names the reader: front (Path, State), entries
// (FM, Project, Repos), front_entries (entries over front's result), events (Path) and time (Text,
// through strptime and timegm alone).
type fcase struct {
	Name    string            `json:"name"`
	Op      string            `json:"op"`
	Path    string            `json:"path"`
	State   string            `json:"state"`
	FM      map[string]string `json:"fm"`
	Project string            `json:"project"`
	Repos   string            `json:"repos"`
	Text    string            `json:"text"`
}

// board is the fixture tree: a project with a Makefile, one without, a repos folder with a repo
// that has a Makefile and one that has not, a stories and an epics folder and their state folders.
type board struct {
	t                                   *testing.T
	root, proj, bare, repos             string
	stories, epics, stState, epicsState string
}

func (b board) write(path string, data []byte) {
	b.t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		b.t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		b.t.Fatal(err)
	}
}

func newBoard(t *testing.T) board {
	root := t.TempDir()
	b := board{t: t, root: root, proj: filepath.Join(root, "proj"), bare: filepath.Join(root, "bare"),
		repos: filepath.Join(root, "repos"), stories: filepath.Join(root, "proj", "board", "stories"),
		epics: filepath.Join(root, "proj", "board", "epics"), stState: filepath.Join(root, "state", "stories"),
		epicsState: filepath.Join(root, "state", "epics")}
	for _, f := range []string{
		filepath.Join(b.proj, "Makefile"), filepath.Join(b.proj, "lint"), filepath.Join(b.proj, "x.sh"),
		filepath.Join(b.repos, "other", "Makefile"), filepath.Join(b.repos, "noMake", "lib.sh"),
		filepath.Join(b.bare, "x.sh"),
	} {
		b.write(f, []byte("x\n"))
	}
	for _, d := range []string{filepath.Join(b.proj, "dir"), filepath.Join(b.repos, "other", "sub")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return b
}

// story writes a story file, and its state file when state is not nil, and gives its front case.
func (b board) story(name, slug string, text, state []byte) fcase {
	b.write(filepath.Join(b.stories, slug+".md"), text)
	if state != nil {
		b.write(filepath.Join(b.stState, slug), state)
	}
	return fcase{Name: name, Op: "front", Path: filepath.Join(b.stories, slug+".md"), State: b.stState}
}

// stateLines is a state file as state_set writes it: one key: value line each.
func stateLines(lines ...string) []byte { return []byte(strings.Join(lines, "\n") + "\n") }

func frontCases(b board) []fcase {
	ready := []byte(item("s", "status: ready", "kind: code", "touches: [lib.sh]"))
	blocked := []byte(item("s", "status: blocked", "kind: code", "touches: [lib.sh]"))
	review := stateLines("status: review", "status@base: ready", "prs: https://github.com/o/r/pull/10", "prs@base:")
	cs := []fcase{
		b.story("no state file", "nostate", ready, nil),
		b.story("board_state's s: review in state over the ready it was written on", "bs-s", ready, review),
		b.story("board_state's s: a later commit of blocked wins over the state's review", "bs-s2", blocked, review),
		b.story("board_state's m: prs only in state", "bs-m",
			[]byte(item("m", "status: ready", "kind: code", "costs: money")), stateLines("prs: https://github.com/o/r/pull/20", "prs@base:")),
		b.story("state with no @base wins", "nobase", ready, stateLines("status: review")),
		b.story("an @base for a key the file lacks, not empty: the file's missing value stays", "lackbase",
			ready, stateLines("held_by: par", "held_by@base: x")),
		b.story("an empty @base for a key the file lacks: the state wins", "lackempty", ready, stateLines("held_by: par", "held_by@base:")),
		b.story("compared before trimming: the file's trailing space is no match", "trimfile",
			[]byte(item("t", "status: ready ", "kind: code")), stateLines("status: review", "status@base: ready")),
		b.story("compared before trimming: an @base with the trailing space matches", "trimbase",
			[]byte(item("t", "status: ready ", "kind: code")), stateLines("status: review", "status@base: ready ")),
		b.story("state values trimmed, U+001F and ideographic space too", "trimstate",
			ready, stateLines("status:   review\x1f　", "prs: \tu/1  ")),
		b.story("a state key repeated: its first value wins", "repeat", ready, stateLines("status: review", "status: done")),
		b.story("a state file read past ---, with blank lines", "pastdash", ready, stateLines("---", "status: review", "", "---", "epic: e")),
		b.story("CRLF story and state", "crlf", []byte("---\r\nstatus: ready\r\nkind: code\r\n---\r\n"),
			[]byte("status: review\r\nstatus@base: ready\r\n")),
		b.story("a lone CR is a newline in both", "lonecr", []byte("---\rstatus: ready\rkind: code\r---\r"), []byte("status: review\rstatus@base: ready\r")),
		b.story("non-UTF-8 bytes in the story and state", "badutf",
			[]byte("---\nstatus: re\xffady\nk\xc3: v\xe2\x82\n---\n"), []byte("status: rev\xc0\xafiew\nstatus@base: re\xffady\nk\xc3@base: v\xe2\x82\n")),
		b.story("an @base in the story file itself is kept", "basefile", []byte(item("b", "status: ready", "status@base: x")), stateLines("status@base: y")),
		b.story("an empty state file", "emptystate", ready, []byte{}),
		b.story("a non-ASCII slug", "café", ready, stateLines("status: review")),
		b.story("a story file with no front matter", "nofm", []byte("# title\nstatus: ready\n"), stateLines("status: review")),
		{Name: "a missing story file", Op: "front", Path: filepath.Join(b.stories, "gone.md"), State: b.stState},
		{Name: "a state folder that is a file", Op: "front", Path: filepath.Join(b.stories, "nostate.md"), State: filepath.Join(b.proj, "x.sh")},
		{Name: "a story file that is a folder", Op: "front", Path: filepath.Join(b.proj, "dir"), State: b.stState},
	}
	// A state file that is a folder, and a two-letter name whose state name is "", the state folder.
	if err := os.MkdirAll(filepath.Join(b.stState, "isdir"), 0o755); err != nil {
		b.t.Fatal(err)
	}
	cs = append(cs, b.story("a state file that is a folder", "isdir", ready, nil))
	b.write(filepath.Join(b.stories, "ab"), ready)
	cs = append(cs, fcase{Name: "a name of 3 characters or fewer reads the state folder", Op: "front", Path: filepath.Join(b.stories, "ab"), State: b.stState})

	// An epic and a story of one slug keep separate state (board_state's same).
	b.write(filepath.Join(b.epics, "same.md"), []byte(item("same", "status: active")))
	b.write(filepath.Join(b.epicsState, "same"), stateLines("status: ready"))
	b.write(filepath.Join(b.stState, "same"), stateLines("status: review"))
	b.write(filepath.Join(b.stories, "same.md"), ready)
	cs = append(cs,
		fcase{Name: "board_state's same: the epic's state", Op: "front", Path: filepath.Join(b.epics, "same.md"), State: b.epicsState},
		fcase{Name: "board_state's same: the story's state", Op: "front", Path: filepath.Join(b.stories, "same.md"), State: b.stState})
	return cs
}

func entriesCases(b board) []fcase {
	in := func(name, touches string, fm ...string) fcase {
		m := map[string]string{"touches": touches}
		for i := 0; i+1 < len(fm); i += 2 {
			m[fm[i]] = fm[i+1]
		}
		return fcase{Name: name, Op: "entries", FM: m, Project: b.proj, Repos: b.repos}
	}
	bare := func(c fcase) fcase { c.Project, c.Name = b.bare, c.Name+", in a project with no Makefile"; return c }
	cs := []fcase{
		in("a file and a part, and a bare file", "[x.sh:f run, y.sh]"),
		in("parts with no file go to the entry before", "[x.sh:f, g, h run]"),
		in("a part named as a file the checkout has is a file", "[x.sh:f, lint]"),
		in("Makefile:lint with a Makefile", "[x.sh:f, Makefile:lint]"),
		bare(in("Makefile:lint", "[x.sh:f, Makefile:lint]")),
		in("Makefile:lint first is a file", "[Makefile:lint, x.sh]"),
		in("a folder is no file", "[x.sh:f, dir]"),
		in("commas inside parentheses", "[x.sh (the f, g and h parts), y.sh: k]"),
		in("nested parentheses and a ) with none open", "[a.sh (b (c, d), e), f), g.sh]"),
		in("a repo prefix", "[other: lib.sh:f, proj: z.sh, other: lint]"),
		in("a repo prefix's Makefile", "[lib.sh:f, other: Makefile:lint, noMake: Makefile:lint]"),
		in("a part after a prefixed entry keeps its repo", "[other: lib.sh:f, g, noMake: h]"),
		in("fm's repo", "[Makefile:lint, lib.sh, Makefile:check]", "repo", "noMake"),
		in("fm's repo is the project's own name", "[x.sh:f, lint, Makefile:lint]", "repo", "proj"),
		in("fm's repo an absolute path", "[a.sh, Makefile:lint]", "repo", filepath.Join(b.repos, "other")),
		in("a prefix with nothing after it is skipped", "[x.sh, other: , other:  ]"),
		in("a colon with no space is no prefix", "[x.sh, other:lint]"),
		in("a prefix of a character outside its class", "[x.sh, oth+er: y.sh]"),
		in("empty parts", "[, x.sh,, ,y.sh, ]"),
		in("empty brackets", "[]"),
		in("no brackets, spaces around", "  x.sh:f ,  y.sh  "),
		in("brackets inside the spaces", " [[x.sh]] "),
		in("a head with spaces and no colon", "[x.sh, a b c]"),
		in("an empty head", "[x.sh, :f]"),
		in("a head with a / or a . is a file", "[x.sh:f, sub/thing, .github]"),
		in("a newline ends a prefix's match", "[x.sh, other: y.sh\nz]"),
		in("Unicode spaces around parts", "[　x.sh:f\x1f,  g ]"),
		in("non-ASCII names", "[café.sh:é f, ü]"),
		{Name: "no touches", Op: "entries", FM: map[string]string{"status": "ready"}, Project: b.proj, Repos: b.repos},
		{Name: "a project dir ending in /", Op: "entries", FM: map[string]string{"touches": "[x.sh:f, lint]", "repo": "proj"}, Project: b.proj + "/", Repos: b.repos},
	}
	b.write(filepath.Join(b.stories, "chain.md"), []byte(item("chain", "status: ready", "touches: [x.sh:f]")))
	b.write(filepath.Join(b.stState, "chain"), stateLines("touches: [other: lib.sh:f, Makefile:lint, g]", "repo: other"))
	return append(cs, fcase{Name: "front's touches and repo from state, then entries", Op: "front_entries",
		Path: filepath.Join(b.stories, "chain.md"), State: b.stState, Project: b.proj, Repos: b.repos})
}

// row is an events.tsv line of its columns.
func row(cols ...string) string { return strings.Join(cols, "\t") }

func eventsCases(b board) []fcase {
	file := func(name, slug string, data []byte) fcase {
		p := filepath.Join(b.root, "events", slug+".tsv")
		b.write(p, data)
		return fcase{Name: name, Op: "events", Path: p}
	}
	lines := func(ls ...string) []byte { return []byte(strings.Join(ls, "\n") + "\n") }
	tail := eventsoutcome.Sep + "k=v"
	fixture, err := os.ReadFile(filepath.Join("..", "..", "tests", "fixtures", "events", "v0.29.1-sample.tsv"))
	if err != nil {
		b.t.Fatal(err)
	}
	// events_tail_flow_test.sh's synthetic rows, added to the fixture, then the tailed copy with
	// every row's outcome ending in the tail.
	flow := append(append([]byte{}, fixture...), lines(
		row("2026-10-26T01:08:11Z", "story", "zzan", "wa:pa", "ok"), row("2026-10-26T05:30:00Z", "review", "zzau", "wa:pa", "ok"),
		row("2026-10-28T10:00:00Z", "conduct", "zzsyn", "wa:pa", "ok"), row("2026-10-28T10:05:00Z", "incident", "conduct-zzsyn", "-", "api-error"))...)
	var tailed []string
	for _, l := range strings.Split(strings.TrimSuffix(string(flow), "\n"), "\n") {
		tailed = append(tailed, l+tail)
	}
	return []fcase{
		file("the v0.29.1 sample", "sample", fixture),
		file("events_tail_flow's rows", "flow", flow),
		file("events_tail_flow's tailed copy", "tailed", lines(tailed...)),
		file("ok outcomes, with and without tails", "outcomes", lines(
			row("2026-11-20T10:00:00Z", "story", "a", "w:p", "ok"),
			row("2026-11-20T10:00:01Z", "story", "b", "w:p", "ok"+tail),
			row("2026-11-20T10:00:02Z", "hold", "c", "w:p", "ok (stacked)"+tail),
			row("2026-11-20T10:00:03Z", "story", "d", "w:p", "okay"),
			row("2026-11-20T10:00:04Z", "story", "e", "w:p", "ok("),
			row("2026-11-20T10:00:05Z", "story", "f", "w:p", "fail"+eventsoutcome.Sep+"ok"),
			row("2026-11-20T10:00:06Z", "story", "g", "w:p", " ok"),
			row("2026-11-20T10:00:07Z", "story", "h", "w:p", "ok"+eventsoutcome.Sep),
			row("2026-11-20T10:00:08Z", "story", "i", "w:p"),
			row("2026-11-20T10:00:09Z", "story", "j", "w:p", "ok", "extra"),
			row("2026-11-20T10:00:10Z", "story", "k", "w:p", "ok ~~"),
		)),
		file("two lines in one second keep their order", "onesec", lines(
			row("2026-11-20T10:00:00Z", "report", "e", "w:p", "ok"), row("2026-11-20T10:00:00Z", "conduct", "e", "w:p", "ok"),
			row("2026-11-20T10:00:00Z", "story", "a", "w:p", "ok"), row("2026-11-20T10:00:00Z", "story", "a", "w:p", "ok"),
		)),
		file("bad times", "badtimes", lines(
			row("2026-13-01T10:00:00Z", "story", "a", "w:p", "ok"), row("2026-02-30T10:00:00Z", "story", "a", "w:p", "ok"),
			row("2026-02-29T10:00:00Z", "story", "a", "w:p", "ok"), row("2024-02-29T10:00:00Z", "story", "a", "w:p", "ok"),
			row("2026-11-20 10:00:00", "story", "a", "w:p", "ok"), row("", "story", "a", "w:p", "ok"),
			row("2026-11-20T10:00:00Z ", "story", "a", "w:p", "ok"), row("2026-1-5T1:2:3Z", "story", "a", "w:p", "ok"),
			row("2026-11-20t10:00:00z", "story", "a", "w:p", "ok"), row("2026-11-20T10:00:60Z", "story", "a", "w:p", "ok"),
		)),
		file("CRLF, a lone CR, and bad UTF-8", "crlf", []byte(
			row("2026-11-20T10:00:00Z", "story", "a", "w:p", "ok")+"\r\n"+row("2026-11-20T10:00:01Z", "story", "b\xff", "w:p", "ok")+"\r"+
				row("2026-11-20T10:00:02Z", "sto\xc3ry", "c", "w:p", "ok\xe2\x82")+"\n"+row("2026-11-20T10:00:03Z", "story", "d", "w:p", "ok"))),
		file("no last newline", "nonl", []byte(row("2026-11-20T10:00:00Z", "story", "a", "w:p", "ok"))),
		file("an empty file", "empty", []byte{}),
		{Name: "a missing file", Op: "events", Path: filepath.Join(b.root, "events", "gone.tsv")},
		{Name: "a folder", Op: "events", Path: filepath.Join(b.root, "events")},
	}
}

// timeCases are strptime inputs past the ones the events files hold: each field's edges.
func timeCases() []fcase {
	var cs []fcase
	for _, s := range []string{
		"1970-01-01T00:00:00Z", "0001-01-01T00:00:00Z", "0000-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "1969-12-31T23:59:59Z",
		"2026-00-01T00:00:00Z", "2026-1-01T00:00:00Z", "2026-01-1T00:00:00Z", "2026-01- 1T00:00:00Z", "2026-01-0T00:00:00Z",
		"2026-01-00T00:00:00Z", "2026-01-32T00:00:00Z", "2026-04-31T00:00:00Z", "2026-01-31T00:00:00Z", "2026-012-01T00:00:00Z",
		"2026-01-01T24:00:00Z", "2026-01-01T23:60:00Z", "2026-01-01T23:59:61Z", "2026-01-01T23:59:62Z", "2026-12-31T23:59:61Z",
		"2026-01-01T9:9:9Z", "2026-01-01T09:09:9Z", "2026-01-01T009:00:00Z", "26-01-01T00:00:00Z", "20266-01-01T00:00:00Z",
		"2026-01-01T00:00:00", "2026-01-01T00:00:00ZZ", "2026-01-01T00:00Z", "2026-01-01T00:00:00+00:00", "2026/01/01T00:00:00Z",
		"٢٠٢٦-01-01T00:00:00Z", "2026-01-1٥T00:00:00Z", "2026-01-01T1٩:٥٥:９Z",
		"2026-01-01T٩:00:00Z", "2026-01-01T00:00:９Z", "2026-١-01T00:00:00Z", "2026-01-١T00:00:00Z", "\U0001D7CE\U0001D7D0\U0001D7D2\U0001D7D4-01-01T00:00:00Z",
		"2026-01-01T00:00:00ẓ", "2026-01-01ţ̃T00:00:00Z", "-2026-01-01T00:00:00Z", "+026-01-01T00:00:00Z",
	} {
		cs = append(cs, fcase{Name: "time " + strconv.Quote(s), Op: "time", Text: s})
	}
	return cs
}

// pyFloat is f as Python's repr writes it, for the values ok_events gives: a shortest form that
// reads back, in fixed point with at least one decimal, and in exponent form past 1e16 or below 1e-4.
func pyFloat(f float64) string {
	if a := max(f, -f); a != 0 && (a < 1e-4 || a >= 1e16) {
		return strconv.FormatFloat(f, 'e', -1, 64)
	}
	s := strconv.FormatFloat(f, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		s += ".0"
	}
	return s
}

// goFiles runs c through the Go readers.
func goFiles(t *testing.T, c fcase) string {
	t.Helper()
	st := store.Files{}
	entries := func(es []Entry) string {
		q := make([]string, len(es))
		for i, e := range es {
			q[i] = pyList([]string{e.Repo, e.File, e.Part})
		}
		return "[" + strings.Join(q, ", ") + "]"
	}
	switch c.Op {
	case "front":
		fm, err := Front(st, c.Path, c.State)
		if err != nil {
			return `"error"`
		}
		return pyMap(fm)
	case "entries":
		return entries(Entries(st, c.FM, c.Project, c.Repos))
	case "front_entries":
		fm, err := Front(st, c.Path, c.State)
		if err != nil {
			return `"error"`
		}
		return entries(Entries(st, fm, c.Project, c.Repos))
	case "events":
		ev, err := OkEvents(st, c.Path)
		if err != nil {
			return `"error"`
		}
		return pyEvents(ev)
	case "time":
		if secs, ok := parseTime(c.Text); ok {
			return strconv.FormatInt(secs, 10)
		}
		return "null"
	}
	t.Fatalf("case %q: unknown op %q", c.Name, c.Op)
	return ""
}

// pyEvents is ok_events' map as the driver prints it: [command, target, [secs, ...]] rows sorted.
func pyEvents(ev map[EventKey][]float64) string {
	keys := make([]EventKey, 0, len(ev))
	for k := range ev {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Command != keys[j].Command {
			return keys[i].Command < keys[j].Command
		}
		return keys[i].Target < keys[j].Target
	})
	rows := make([]string, len(keys))
	for i, k := range keys {
		ts := make([]string, len(ev[k]))
		for j, f := range ev[k] {
			ts[j] = pyFloat(f)
		}
		rows[i] = "[" + pyString(k.Command) + ", " + pyString(k.Target) + ", [" + strings.Join(ts, ", ") + "]]"
	}
	return "[" + strings.Join(rows, ", ") + "]"
}

// TestFilesMatchPython runs every file-reader case through touches_rows.py and through the Go over
// the same fixture tree, and wants the two outputs the same, byte for byte. With no python3, or a
// driver that fails, it fails.
func TestFilesMatchPython(t *testing.T) {
	b := newBoard(t)
	var cs []fcase
	cs = append(cs, frontCases(b)...)
	cs = append(cs, entriesCases(b)...)
	cs = append(cs, eventsCases(b)...)
	cs = append(cs, timeCases()...)
	in, err := json.Marshal(cs)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pyWait)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-I", "-B", "-c", filesDriver, pyLib)
	cmd.Stdin = bytes.NewReader(in)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	py, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 over touches_rows.py: %v\n%s", err, stderr.String())
	}
	pyLines := strings.Split(strings.TrimSuffix(string(py), "\n"), "\n")
	if len(pyLines) != len(cs) {
		t.Fatalf("python3 printed %d lines for %d cases", len(pyLines), len(cs))
	}
	for i, c := range cs {
		if g := goFiles(t, c); g != pyLines[i] {
			t.Errorf("case %q (%s): python %s, go %s", c.Name, c.Op, clip(pyLines[i]), clip(g))
		}
	}
}

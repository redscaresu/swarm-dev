package resend

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

// The values every fixture hands the program but the ones it names: own_panes' output, the backlog
// conductor's name as conductor_name gives it, and AGENT_NAME_MAX.
const (
	fxPanes   = "w1:p1 w1:p2\tw1:p3\nw1:p4 w1:p5 w1:p6"
	fxBacklog = "conduct-backlog-proj-0123abcd"
	fxNameMax = 32
)

// fixture is one run of the program. Each want is what the inline Python of resend_pass printed and
// left on the same files: the PR that added this file records the command that ran it.
type fixture struct {
	name    string
	agents  string            // herdr's agent list
	events  string            // events.tsv's bytes
	resent  *string           // LEAD_RESENT's bytes; nil for no file
	markers map[string]string // each marker's file name in the briefs folder, and its bytes
	rows    []string          // the rows printed, each without its newline
	removed []string          // the markers removed, by file name
	err     error             // the program's failure as a whole
}

// list is herdr's agent list of the agents given as name, pane and status triples; a status of "" is
// an agent listed with none.
func list(triples ...string) string {
	var a []string
	for i := 0; i+2 < len(triples); i += 3 {
		s := `"name": "` + triples[i] + `", "pane_id": "` + triples[i+1] + `"`
		if triples[i+2] != "" {
			s += `, "agent_status": "` + triples[i+2] + `"`
		}
		a = append(a, "{"+s+"}")
	}
	return `{"result": {"agents": [` + strings.Join(a, ", ") + `]}}`
}

// ev is one events.tsv line of five columns.
func ev(at, cmd, target, outcome string) string {
	return at + "\t" + cmd + "\t" + target + "\tw1:p0\t" + outcome + "\n"
}

// row is one printed row from its nine fields.
func row(f ...string) string { return strings.Join(f, "\t") }

func text(s string) *string { return &s }

// runFixture runs the program on fx's files, the markers read in name order as the entry reads them.
func runFixture(fx fixture) (rows, removed []string, err error) {
	in := Input{Agents: []byte(fx.agents), Own: fxPanes, Backlog: fxBacklog, NameMax: fxNameMax,
		Events: File{Path: "events.tsv", Data: []byte(fx.events)}, Resent: File{Path: "resend", Err: errors.New("no file")}}
	if fx.resent != nil {
		in.Resent = File{Path: "resend", Data: []byte(*fx.resent)}
	}
	names := make([]string, 0, len(fx.markers))
	for n := range fx.markers {
		names = append(names, n)
	}
	slices.Sort(names)
	for _, n := range names {
		in.Markers = append(in.Markers, File{Path: "/briefs/" + n, Data: []byte(fx.markers[n])})
	}
	rows, remove, err := Rows(in)
	for _, p := range remove {
		removed = append(removed, strings.TrimPrefix(p, "/briefs/"))
	}
	return rows, removed, err
}

// check runs each fixture and compares its rows, removed markers and failure with the Python's.
func check(t *testing.T, fixtures []fixture) {
	t.Helper()
	for _, fx := range fixtures {
		rows, removed, err := runFixture(fx)
		if !slices.Equal(rows, fx.rows) {
			t.Errorf("%s: rows\n%q\nwant\n%q", fx.name, rows, fx.rows)
		}
		if !slices.Equal(removed, fx.removed) {
			t.Errorf("%s: removed %q, want %q", fx.name, removed, fx.removed)
		}
		if !errors.Is(err, fx.err) || (err == nil) != (fx.err == nil) {
			t.Errorf("%s: error %v, want %v", fx.name, err, fx.err)
		}
	}
}

// resentKey is a delivery's line in the resent file, with words after it.
func resentKey(n, at, cmd, k string, words ...string) string {
	return strings.Join(append([]string{n, at, cmd, k}, words...), "\t") + "\n"
}

// If the mode stops telling a delivery line not yet checked (new) from the first read after its Enter
// (after), or stops passing over a line rechecked or checked with no Enter, a row changes and this goes red.
func TestModes(t *testing.T) {
	alpha := list("alpha", "w1:p1", "idle")
	story := ev("T1", "story", "alpha", "ok")
	check(t, []fixture{
		{name: "a new delivery", agents: alpha, events: story,
			rows: []string{row("w1:p1", "alpha", "T1", "story", "1", "alpha", "builder", "new", "-")}},
		{name: "the after mode", agents: alpha, events: story,
			resent: text(resentKey("alpha", "T1", "story", "1") + resentKey("alpha", "T1", "story", "1", "resent")),
			rows:   []string{row("w1:p1", "alpha", "T1", "story", "1", "alpha", "builder", "after", "-")}},
		{name: "rechecked", agents: alpha, events: story,
			resent: text(resentKey("alpha", "T1", "story", "1") + resentKey("alpha", "T1", "story", "1", "resent") +
				resentKey("alpha", "T1", "story", "1", "rechecked"))},
		{name: "checked, with no Enter", agents: alpha, events: story,
			resent: text(resentKey("alpha", "T1", "story", "1"))},
		{name: "a resent line for an older delivery", agents: alpha, events: story + ev("T2", "restart", "alpha", "ok"),
			resent: text(resentKey("alpha", "T1", "story", "1") + resentKey("alpha", "T1", "story", "1", "resent")),
			rows:   []string{row("w1:p1", "alpha", "T2", "restart", "1", "alpha", "builder", "new", "-")}},
	})
}

// If a marker stops being kept for an idle agent, or removed for one herdr lists working, blocked or done,
// lists in another pane or not at all, or starts being removed for an agent with no status or another
// one, the rows or the removed markers change and this goes red.
func TestMarkers(t *testing.T) {
	check(t, []fixture{{
		name: "a marker kept for an idle agent and removed for a gone, working, blocked and done one",
		agents: list("alpha", "w1:p1", "idle", "beta", "w1:p2", "working", "gamma", "w1:p3", "blocked",
			"delta", "w1:p4", "done", "eps", "w1:p5", "", "zeta", "w1:p6", "starting", "omega", "w9:p9", "idle"),
		markers: map[string]string{
			"alpha.unsent":     "alpha w1:p1 builder\npid 1\n",
			"alpha-old.unsent": "alpha w1:p2 builder\npid 1\n",
			"beta.unsent":      "beta w1:p2 builder\npid 1\n",
			"gamma.unsent":     "gamma w1:p3 builder\npid 1\n",
			"delta.unsent":     "delta w1:p4 builder\npid 1\n",
			"eps.unsent":       "eps w1:p5 builder\npid 1\n",
			"zeta.unsent":      "zeta w1:p6 builder\npid 1\n",
			"omega.unsent":     "omega w9:p9 builder\npid 1\n",
			"ghost.unsent":     "ghost w1:p1 builder\npid 1\n",
		},
		rows:    []string{row("w1:p1", "alpha", "-", "-", "-", "-", "-", "-", "alpha")},
		removed: []string{"alpha-old.unsent", "beta.unsent", "delta.unsent", "gamma.unsent", "ghost.unsent", "omega.unsent"},
	}, {
		name:    "a marked agent with a delivery of its own",
		agents:  list("alpha", "w1:p1", "idle"),
		events:  ev("T1", "story", "alpha", "ok"),
		resent:  text(resentKey("alpha", "T1", "story", "1")),
		markers: map[string]string{"alpha-x.unsent": "alpha\tw1:p1 builder\r\n"},
		rows:    []string{row("w1:p1", "alpha", "T1", "story", "1", "alpha", "builder", "-", "alpha-x")},
	}, {
		name:   "a short marker",
		agents: list("alpha", "w1:p1", "idle"),
		markers: map[string]string{"one.unsent": "alpha\nw1:p1\n", "none.unsent": "", "blank.unsent": " \n",
			"cr.unsent": "ghost\rw1:p1\n"},
	}})
}

// If a tell stops taking the stem and role of its agent's last start line, or of the name it was told
// by when there is none, or the backlog conductor's, the stem and role fields change and this goes red.
func TestTellRole(t *testing.T) {
	check(t, []fixture{{
		name: "a tell taking its start's role",
		agents: list("helper", "w1:p1", "idle", "solo", "w1:p2", "idle", "review-y", "w1:p3", "idle",
			"conduct-e1", "w1:p4", "idle", "rev", "w1:p5", "idle"),
		events: ev("T1", "agent", "helper", "ok") + ev("T2", "tell:findings", "helper", "ok") +
			ev("T3", "tell", "solo", "ok") + ev("T4", "tell:nudge", "review-y", "ok") +
			ev("T5", "tell:resume", "conduct-e1", "ok") + ev("T6", "story", "Rev_X", "die: no story") +
			ev("T7", "tell:nudge", "rev", "ok"),
		rows: []string{
			row("w1:p4", "conduct-e1", "T5", "tell:resume", "1", "conduct-e1", "conductor", "new", "-"),
			row("w1:p1", "helper", "T2", "tell:findings", "1", "-", "-", "new", "-"),
			row("w1:p5", "rev", "T7", "tell:nudge", "1", "rev", "builder", "new", "-"),
			row("w1:p3", "review-y", "T4", "tell:nudge", "1", "review-y", "review", "new", "-"),
			row("w1:p2", "solo", "T3", "tell", "1", "solo", "builder", "new", "-"),
		},
	}, {
		name:   "the backlog conductor started",
		agents: list(fxBacklog, "w1:p1", "idle", "conduct-e2", "w1:p2", "idle"),
		events: ev("T1", "conduct", "--backlog", "ok") + ev("T2", "conduct", "e2", "ok (round 2)"),
		rows: []string{
			row("w1:p1", fxBacklog, "T1", "conduct", "1", "conduct-backlog", "conductor", "new", "-"),
			row("w1:p2", "conduct-e2", "T2", "conduct", "1", "conduct-e2", "conductor", "new", "-"),
		},
	}, {
		name:   "the backlog conductor started by its short name",
		agents: list(fxBacklog, "w1:p1", "idle"),
		events: ev("T1", "conduct", "backlog", "ok"),
		rows:   []string{row("w1:p1", fxBacklog, "T1", "conduct", "1", "conduct-backlog", "conductor", "new", "-")},
	}, {
		name:   "the backlog conductor told",
		agents: list(fxBacklog, "w1:p1", "idle"),
		events: ev("T2", "tell:note", fxBacklog, "ok") + ev("T3", "tell", fxBacklog, "ok"),
		rows:   []string{row("w1:p1", fxBacklog, "T3", "tell", "1", "conduct-backlog", "conductor", "new", "-")},
	}, {
		name:   "a tell after a failed start takes that start's role",
		agents: list("helper", "w1:p1", "idle"),
		events: ev("T1", "agent", "helper", "die: no pane") + ev("T2", "tell", "helper", "ok"),
		rows:   []string{row("w1:p1", "helper", "T2", "tell", "1", "-", "-", "new", "-")},
	}})
}

// If a start that failed before sending stops clearing its agent's newest delivery, a failed tell
// starts clearing it, or an outcome that delivered the prompt reads as one that did not, this goes red.
func TestOutcomes(t *testing.T) {
	check(t, []fixture{{
		name:   "a failed start resetting newest",
		agents: list("alpha", "w1:p1", "idle", "beta", "w1:p2", "idle", "gamma", "w1:p3", "idle"),
		events: ev("T1", "story", "alpha", "ok") + ev("T2", "restart", "alpha", "die: no worktree") +
			ev("T1", "story", "beta", "ok") + ev("T2", "tell:findings", "beta", "failed: no pane") +
			ev("T1", "story", "gamma", "die: x") + ev("T2", "tell", "gamma", "ok"),
		rows: []string{
			row("w1:p2", "beta", "T1", "story", "1", "beta", "builder", "new", "-"),
			row("w1:p3", "gamma", "T2", "tell", "1", "gamma", "builder", "new", "-"),
		},
	}, {
		name: "outcomes that delivered, and alike lines counted",
		agents: list("alpha", "w1:p1", "idle", "beta", "w1:p2", "idle", "gamma", "w1:p3", "idle",
			"delta", "w1:p4", "idle", "eps", "w1:p5", "idle"),
		events: ev("T1", "story", "alpha", "ok") + ev("T1", "story", "alpha", "ok ~~ round=1") +
			ev("T1", "escalate", "beta", "ok (stalled: no turn)") +
			ev("T1", "step-up", "gamma", "failed: herdr sent it the brief, then no reply") +
			ev("T1", "step-up:resume", "delta", "failed: it may or may not have the brief") +
			ev("T1", "review-agent", "eps", "failed: the reply to the brief could not be read") +
			ev("T2", "review-agent", "eps", "okay"),
		rows: []string{
			row("w1:p1", "alpha", "T1", "story", "2", "alpha", "builder", "new", "-"),
			row("w1:p2", "beta", "T1", "escalate", "1", "beta", "builder", "new", "-"),
			row("w1:p4", "delta", "T1", "step-up:resume", "1", "delta", "builder", "new", "-"),
			row("w1:p3", "gamma", "T1", "step-up", "1", "gamma", "builder", "new", "-"),
		},
	}, {
		name:   "a 4-column line",
		agents: list("alpha", "w1:p1", "idle", "beta", "w1:p2", "idle"),
		events: "T1\tstory\talpha\tok\n" + "T1\tstory\tbeta\tw1:p0\tok\textra\n",
	}, {
		name:   "lines that deliver no prompt to an idle agent of this project",
		agents: list("alpha", "w1:p1", "idle", "beta", "w1:p2", "working", "gamma", "w9:p9", "idle"),
		events: ev("T1", "tell:note", "alpha", "ok") + ev("T1", "merge", "alpha", "ok") +
			ev("T1", "story", "beta", "ok") + ev("T1", "story", "gamma", "ok"),
	}})
}

// If the agent name rule stops working per byte of the target's UTF-8 (lower-casing A-Z only, a dash for
// each other byte, s before a name that starts with no letter, the cut at AGENT_NAME_MAX), or events.tsv
// stops being read as Python's text mode reads it (bad bytes replaced, \r\n a line end), this goes red.
func TestAgentName(t *testing.T) {
	long := strings.Repeat("abcdefghij", 4)
	check(t, []fixture{{
		name: "a non-ASCII agent name",
		agents: list("caf--", "w1:p1", "idle", "s1abc", "w1:p2", "idle", "s--1", "w1:p3", "idle",
			long[:fxNameMax], "w1:p4", "idle", "al---pha", "w1:p5", "idle", "zoë", "w1:p6", "idle"),
		events: ev("T1", "story", "Café", "ok") + ev("T2", "story", "1ABC", "ok") + ev("T3", "story", "é1", "ok") +
			ev("T4", "story", long, "ok") + strings.TrimSuffix(ev("T5", "story", "al\xffpha", "ok"), "\n") + "\r\n" +
			ev("T6", "story", "zoë", "ok"),
		markers: map[string]string{"zoe.unsent": "zoë w1:p6 builder\n"},
		rows: []string{
			row("w1:p4", long[:fxNameMax], "T4", "story", "1", long, "builder", "new", "-"),
			row("w1:p5", "al---pha", "T5", "story", "1", "-", "-", "new", "-"),
			row("w1:p1", "caf--", "T1", "story", "1", "-", "-", "new", "-"),
			row("w1:p3", "s--1", "T3", "story", "1", "-", "-", "new", "-"),
			row("w1:p2", "s1abc", "T2", "story", "1", "-", "-", "new", "-"),
			row("w1:p6", "zoë", "-", "-", "-", "-", "-", "-", "zoe"),
		},
	}})
}

// If a failure of the program as a whole (a list that is not herdr's JSON, a marker or resent file that is
// not UTF-8) stops failing, or the markers removed before it stop being reported, this goes red.
func TestFailures(t *testing.T) {
	idle := list("alpha", "w1:p1", "idle")
	gone := map[string]string{"a.unsent": "ghost w1:p1\n", "b.unsent": "alpha w1:p1 \xff\n"}
	check(t, []fixture{
		{name: "a list that is not JSON", agents: "herdr: no server", markers: gone, err: ErrList},
		{name: "a list with no result", agents: `{"agents": []}`, err: ErrList},
		{name: "agents that are a number", agents: `{"result": {"agents": 3}}`, err: ErrList},
		{name: "agents that are a non-empty object", agents: `{"result": {"agents": {"a": 1}}}`, err: ErrList},
		{name: "an agent that is a string", agents: `{"result": {"agents": ["alpha"]}}`, err: ErrList},
		{name: "a name that is a list, in this project's pane",
			agents: `{"result": {"agents": [{"name": ["a"], "pane_id": "w1:p1"}]}}`, err: ErrList},
		{name: "a marker that is not UTF-8", agents: idle, markers: gone, removed: []string{"a.unsent"}, err: ErrNotUTF8},
		{name: "a resent file that is not UTF-8", agents: idle, events: ev("T1", "story", "alpha", "ok"),
			resent: text("alpha\tT1\tstory\t1\xff\n"), markers: map[string]string{"a.unsent": "ghost w1:p1\n"},
			removed: []string{"a.unsent"}, err: ErrNotUTF8},
		{name: "agents that are an empty object, and odd values passed over",
			agents: `{"result": {"agents": {}}}`, events: ev("T1", "story", "alpha", "ok")},
		{name: "names and panes that are no strings",
			agents: `{"result": {"agents": [{"name": 7, "pane_id": "w1:p1", "agent_status": "idle"}, ` +
				`{"name": "", "pane_id": ["x"]}, {"name": "alpha", "pane_id": 5, "agent_status": "idle"}, ` +
				`{"name": "beta", "pane_id": "w1:p2", "agent_status": ["idle"]}]}}`,
			events:  ev("T1", "story", "alpha", "ok") + ev("T1", "story", "beta", "ok"),
			markers: map[string]string{"b.unsent": "beta w1:p2\n"}},
	})
}

// If firstLine stops reading a marker as Python's readline does, deciding where a bad byte fails the
// read by the 8192-byte chunks it decodes, this goes red. Each want is python3 3.14's readline().split()
// on the same bytes.
func TestFirstLineReadsAsReadline(t *testing.T) {
	x := func(n int) string { return strings.Repeat("x", n) }
	for _, c := range []struct {
		name, data, want string
		err              bool
	}{
		{"a bad byte after the line end", "a b\n\xff", "", true},
		{"a cut sequence after the line end", "a b\n\xe2\x82", "a b", false},
		{"a cut sequence with no line end", "a b\xe2\x82", "", true},
		{"a cut sequence after a closing \\r", "a b\r\xe2\x82", "", true},
		{"a bad byte after a \\r", "a b\r\xff", "", true},
		{"a bad byte in the first chunk", "a b\n" + x(4996) + "\xff" + x(5000), "", true},
		{"a bad byte the first chunk ends on", "a b\n" + x(8187) + "\xff" + x(5000), "", true},
		{"a bad byte past the first chunk", "a b\n" + x(8188) + "\xff" + x(5000), "a b", false},
		{"a \\r the first chunk ends on", "a b" + x(8188) + "\r\xffy", "", true},
		{"a \\r before the first chunk's end", "a b" + x(8187) + "\rz\xffy", "a b" + x(8187), false},
		{"no line end", "a b", "a b", false},
		{"an empty file", "", "", false},
	} {
		got, err := firstLine([]byte(c.data))
		if got != c.want || (err != nil) != c.err {
			t.Errorf("%s: %.20q, %v; want %.20q, error %v", c.name, got, err, c.want, c.err)
		}
	}
}

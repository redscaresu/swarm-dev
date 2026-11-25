// Package resend holds the row program of resend_pass (bin/lib/lifecycle.sh): from herdr's agent list,
// events.tsv, the lead's resent file and the .unsent markers, it picks the idle agents whose pane the
// pass reads this poll, and the markers that go. It is the Go port of the pass's inline Python program,
// and cmd/swarm's _resend-rows entry runs it for the pass. It reads what the entry hands it and touches no file:
// Rows returns the markers to remove, and the entry removes them.
package resend

import (
	"bytes"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/eventsoutcome"
	"github.com/redscaresu/swarm-dev/internal/pyjson"
	"github.com/redscaresu/swarm-dev/internal/pytext"
)

var (
	// ErrList is an agent list the program fails on: not JSON, or not shaped as herdr's list.
	ErrList = errors.New("resend: the agent list is not herdr's JSON")
	// ErrNotUTF8 is a marker or a resent file that Python's strict UTF-8 read fails on.
	ErrNotUTF8 = errors.New("resend: not UTF-8")
)

// File is one file the program reads: its path, and what reading it gave.
type File struct {
	Path string
	Data []byte
	Err  error
}

// Input is what the row program reads.
type Input struct {
	Agents  []byte // herdr's agent list, the pass's stdin
	Own     string // this project's pane ids, as own_panes prints them, split on whitespace
	Backlog string // the backlog conductor's agent name (conductor_name backlog)
	NameMax int    // AGENT_NAME_MAX, where an agent name is cut
	Events  File   // events.tsv; a failed read is an empty log
	Resent  File   // LEAD_RESENT, the delivery lines the pass is done with; a failed read is none
	Markers []File // each .unsent marker in the briefs folder; a failed read is passed over
}

// The agent statuses the rule names. gone is a marker's agent that herdr does not list in its pane.
const (
	statusIdle  = "idle"
	statusGone  = "gone"
	statusNone  = "-" // herdr lists the agent with no status
	statusOther = ""  // a status that is not a string: it equals none of the others
)

// removed are the statuses whose agent's marker goes: it took a turn, or herdr no longer lists it.
var removed = []string{statusGone, "working", "blocked", "done"}

// markerSuffix ends every marker's file name; the name without it is the brief's stem.
const markerSuffix = ".unsent"

// noValue fills a row's delivery fields for an agent with no delivery, and a stem or role that is none.
const noValue = "-"

// The pass's modes: new for a delivery line not yet checked, after for the first read after its Enter.
const (
	modeNew   = "new"
	modeAfter = "after"
)

// The words a resent file line adds to a delivery's key.
const (
	keyResent    = "\tresent"
	keyRechecked = "\trechecked"
)

// eventCols is how many columns an events.tsv line has; a line with more or fewer is passed over.
const eventCols = 5

// starts are the commands whose target is an agent name as it is; tell: forms but tell:note are too.
var starts = []string{"story", "escalate", "step-up", "step-up:resume", "restart", "agent", "tell"}

// tellPrefix starts a tell's command; noteTell goes to the conductor's inbox, so it delivers no prompt.
const (
	tellPrefix = "tell"
	noteTell   = "tell:note"
)

// sentNotes are deliver_prompt's failures once herdr may have sent the brief, in sent_note's words.
var sentNotes = []string{"herdr sent it the brief", "may or may not have the brief", "reply to the brief could not be read"}

// Rows returns the rows the program prints, one string per line without its newline, and the markers
// it removes. On an error, the program's failure as a whole, rows is nil and remove holds the markers
// it removed before it failed.
func Rows(in Input) (rows, remove []string, err error) {
	listed, err := listAgents(in.Agents, pyFields(in.Own))
	if err != nil {
		return nil, nil, err
	}
	idle := listed.idle()
	marked := map[string]string{}
	for _, m := range in.Markers {
		if m.Err != nil {
			continue
		}
		line, err := firstLine(m.Data)
		if err != nil {
			return nil, remove, fmt.Errorf("%w: %s", err, m.Path)
		}
		f := pyFields(line)
		if len(f) < 2 {
			continue
		}
		s, ok := listed.status[agentKey{f[0], f[1]}]
		if !ok {
			s = statusGone
		}
		if s == statusIdle {
			marked[f[0]] = strings.TrimSuffix(m.Path[strings.LastIndex(m.Path, "/")+1:], markerSuffix)
		} else if slices.Contains(removed, s) {
			remove = append(remove, m.Path)
		}
	}
	newest := deliveries(in, idle)
	seen, err := seenLines(in.Resent)
	if err != nil {
		return nil, remove, err
	}
	return printed(idle, newest, marked, seen), remove, nil
}

// agentKey is one agent herdr lists: its name and its pane.
type agentKey struct{ name, pane string }

// listing is herdr's list as the program keeps it: each agent with a string name in one of this
// project's panes, in the order herdr first lists it, with the status herdr last gives it.
type listing struct {
	order  []agentKey
	status map[agentKey]string
}

// idle returns each idle agent's pane by its name; for a name idle in two panes, the later one.
func (l listing) idle() map[string]string {
	out := map[string]string{}
	for _, k := range l.order {
		if l.status[k] == statusIdle {
			out[k.name] = k.pane
		}
	}
	return out
}

// listAgents reads herdr's list as json.loads(...)["result"]["agents"] and the program's comprehension
// read it, failing with ErrList where they raise. An agent with a falsy name is passed over; one with a
// name that is no string is kept by Python but can match no agent, so it is left out here.
func listAgents(data []byte, own []string) (listing, error) {
	l := listing{status: map[agentKey]string{}}
	agents, err := agentItems(data)
	if err != nil {
		return l, err
	}
	for _, item := range agents {
		a, ok := item.(pyjson.Object)
		if !ok {
			return l, fmt.Errorf("%w: an agent that is not an object", ErrList)
		}
		name, _ := a.Get("name")
		if !truthy(name) {
			continue
		}
		pane, _ := a.Get("pane_id")
		if !hashable(pane) {
			return l, fmt.Errorf("%w: a pane_id that is a list or an object", ErrList)
		}
		if p, ok := pane.(string); !ok || !slices.Contains(own, p) {
			continue
		}
		if !hashable(name) {
			return l, fmt.Errorf("%w: a name that is a list or an object", ErrList)
		}
		n, ok := name.(string)
		if !ok {
			continue
		}
		k := agentKey{n, pane.(string)}
		if _, held := l.status[k]; !held {
			l.order = append(l.order, k)
		}
		l.status[k] = statusOf(a)
	}
	return l, nil
}

// agentItems returns the list under result.agents. Python iterates an empty object or string as no
// agents, and fails on any other value that is not a list.
func agentItems(data []byte) ([]any, error) {
	v, err := pyjson.Decode(data)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", ErrList, err)
	}
	for _, key := range []string{"result", "agents"} {
		o, ok := v.(pyjson.Object)
		if !ok {
			return nil, fmt.Errorf("%w: no object holds %s", ErrList, key)
		}
		if v, ok = o.Get(key); !ok {
			return nil, fmt.Errorf("%w: no %s", ErrList, key)
		}
	}
	switch a := v.(type) {
	case []any:
		return a, nil
	case pyjson.Object:
		if len(a) == 0 {
			return nil, nil
		}
	case string:
		if a == "" {
			return nil, nil
		}
	}
	return nil, fmt.Errorf("%w: agents is not a list", ErrList)
}

// statusOf is a.get("agent_status") or "-": a falsy status is statusNone, and one that is no string
// statusOther.
func statusOf(a pyjson.Object) string {
	v, _ := a.Get("agent_status")
	if !truthy(v) {
		return statusNone
	}
	if s, ok := v.(string); ok {
		return s
	}
	return statusOther
}

// truthy is a decoded JSON value's truth in Python.
func truthy(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case bool:
		return x
	case string:
		return x != ""
	case int64:
		return x != 0
	case float64:
		return x != 0
	case []any:
		return len(x) > 0
	case pyjson.Object:
		return len(x) > 0
	}
	return true // a BigInt, which is never 0
}

// hashable is whether Python can put a decoded JSON value in a set or use it as a dict key.
func hashable(v any) bool {
	switch v.(type) {
	case []any, pyjson.Object:
		return false
	}
	return true
}

// delivery is an agent's newest delivery line: its time, command and count among alike lines, and
// the brief stem and role an .unsent marker takes for it.
type delivery struct {
	at, cmd    string
	n          int
	stem, role string
}

// deliveries reads events.tsv as the program does, and returns each idle agent's newest delivery. An
// agent whose newest start failed before sending has none.
func deliveries(in Input, idle map[string]string) map[string]delivery {
	newest := map[string]delivery{}
	if in.Events.Err != nil {
		return newest
	}
	alike := map[[3]string]int{}
	started := map[string][2]string{}
	for _, line := range strings.Split(universal(pytext.DecodeReplace(in.Events.Data)), "\n") {
		f := strings.Split(line, "\t")
		if len(f) != eventCols {
			continue
		}
		c, t := f[1], f[2]
		n, ok := agentOf(c, t, in.Backlog, in.NameMax)
		if !ok {
			continue
		}
		if _, ok := idle[n]; !ok {
			continue
		}
		var sr [2]string
		if strings.HasPrefix(c, tellPrefix) {
			var held bool
			if sr, held = started[n]; !held {
				sr = told(n, t, in.Backlog)
			}
		} else {
			sr = stem(c, t)
			started[n] = sr
		}
		if sent(eventsoutcome.Outcome(f)) {
			k := [3]string{n, f[0], c}
			alike[k]++
			newest[n] = delivery{at: f[0], cmd: c, n: alike[k], stem: sr[0], role: sr[1]}
		} else if !strings.HasPrefix(c, tellPrefix) {
			// A start that failed before sending may still have opened the pane and recorded its
			// session: whatever is in the box is not an older brief.
			delete(newest, n)
		}
	}
	return newest
}

// agentOf is the agent a delivery line's command c and target t delivered to, and false for a line
// that delivers no prompt.
func agentOf(c, t, backlog string, max int) (string, bool) {
	switch {
	case slices.Contains(starts, c) || strings.HasPrefix(c, tellPrefix+":") && c != noteTell:
		return agentName(t, max), true
	case c == "review-agent":
		return agentName("review-"+t, max), true
	case c == "conduct" && (t == "--backlog" || t == "backlog"):
		return backlog, true
	case c == "conduct":
		return agentName("conduct-"+t, max), true
	}
	return "", false
}

// sent reports whether an outcome delivered the prompt: ok (an escalate line reads ok (<trigger>: ...)),
// or a deliver_prompt failure once herdr may have sent it.
func sent(o string) bool {
	if o == "ok" || strings.HasPrefix(o, "ok (") {
		return true
	}
	for _, w := range sentNotes {
		if strings.Contains(o, w) {
			return true
		}
	}
	return false
}

// agentName is the program's own agent name rule, per byte of x's UTF-8: A-Z lower-cased, any byte but
// a-z, 0-9, _ and - a dash, s before a name that does not start with a-z, then cut at max bytes.
func agentName(x string, max int) string {
	b := []byte(x)
	for i, c := range b {
		switch {
		case c >= 'A' && c <= 'Z':
			b[i] = c + 'a' - 'A'
		case !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_' || c == '-'):
			b[i] = '-'
		}
	}
	if len(b) == 0 || b[0] < 'a' || b[0] > 'z' {
		b = append([]byte("s"), b...)
	}
	return string(b[:min(max, len(b))])
}

// stem is the brief stem and role a start's marker takes: none for an agent started by name.
func stem(c, t string) [2]string {
	switch c {
	case "agent":
		return [2]string{noValue, noValue}
	case "review-agent":
		return slug("review-"+t, "review")
	case "conduct":
		return slug("conduct-"+strings.TrimLeft(t, "-"), "conductor")
	}
	return slug(t, "builder")
}

// told is the stem and role a tell takes when no start line of its agent came before it: the backlog
// conductor's, else the one the name it was told by says.
func told(n, t, backlog string) [2]string {
	if n == backlog {
		return [2]string{"conduct-backlog", "conductor"}
	}
	switch {
	case strings.HasPrefix(t, "conduct-"):
		return slug(t, "conductor")
	case strings.HasPrefix(t, "review-"):
		return slug(t, "review")
	}
	return slug(t, "builder")
}

// slug is s and role when s is a non-empty run of a-z, 0-9 and -, and none otherwise.
func slug(s, role string) [2]string {
	if s == "" || strings.TrimLeft(s, "abcdefghijklmnopqrstuvwxyz0123456789-") != "" {
		return [2]string{noValue, noValue}
	}
	return [2]string{s, role}
}

// seenLines is the resent file's lines as a set, as open(path, encoding="utf-8").read().splitlines()
// reads them: no set for a failed read, and ErrNotUTF8 for a file that is not UTF-8.
func seenLines(f File) (map[string]bool, error) {
	seen := map[string]bool{}
	if f.Err != nil {
		return seen, nil
	}
	if !utf8.Valid(f.Data) {
		return nil, fmt.Errorf("%w: %s", ErrNotUTF8, f.Path)
	}
	for _, l := range strings.FieldsFunc(universal(string(f.Data)), lineBoundary) {
		seen[l] = true
	}
	return seen, nil
}

// lineBoundary is whether str.splitlines splits at r (\r is gone once text mode has read the file).
func lineBoundary(r rune) bool {
	switch r {
	case '\n', '\r', '\v', '\f', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
		return true
	}
	return false
}

// universal is text mode's newline translation, which open() adds: \r\n and a lone \r become \n.
func universal(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
}

// pyFields is str.split(): s cut at each run of what Python's str.isspace takes as whitespace, which is
// Go's unicode.IsSpace and the four separators 0x1c to 0x1f.
func pyFields(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool { return unicode.IsSpace(r) || r >= 0x1c && r <= 0x1f })
}

// pyChunk is how many bytes Python's text reader (TextIOWrapper) reads and decodes at a time.
const pyChunk = 8192

// firstLine is a marker's first line, without its end, as open(path, encoding="utf-8").readline() reads
// it. ErrNotUTF8 is where that read raises: an invalid byte anywhere in the chunks it decodes, which run
// to the end of the chunk that holds the line's end (one more when that end is a \r the chunk ends on,
// as a \n may follow it), or a sequence cut short at the end of a file with no line end in it.
func firstLine(b []byte) (string, error) {
	end := 0
	for {
		n := min(pyChunk, len(b)-end)
		end += n
		final := n == 0 // the read that returned nothing: the decoder's last call
		whole := end
		if !final {
			whole -= cutTail(b[:end])
		}
		if !utf8.Valid(b[:whole]) {
			return "", ErrNotUTF8
		}
		if i := bytes.IndexAny(b[:whole], "\r\n"); i >= 0 && (final || b[i] == '\n' || i < whole-1) {
			return string(b[:i]), nil
		}
		if final {
			return string(b), nil
		}
	}
}

// cutTail is how many bytes at the end of b start a UTF-8 sequence that more bytes could complete,
// which the decoder holds for its next call rather than fail on.
func cutTail(b []byte) int {
	for k := 1; k < utf8.UTFMax && k <= len(b); k++ {
		c := b[len(b)-k]
		if c < utf8.RuneSelf {
			return 0
		}
		if utf8.RuneStart(c) {
			if utf8.FullRune(b[len(b)-k:]) {
				return 0
			}
			return k
		}
	}
	return 0
}

// printed is the program's rows: for each idle agent with a delivery or a marker, sorted by name, its
// pane, name, delivery fields, mode and marker stem, when the mode is not - or it has a marker.
func printed(idle map[string]string, newest map[string]delivery, marked map[string]string, seen map[string]bool) []string {
	var rows []string
	for _, n := range candidates(idle, newest, marked) {
		at, cmd, k, st, role, mode := noValue, noValue, noValue, noValue, noValue, noValue
		if d, ok := newest[n]; ok {
			at, cmd, k, st, role = d.at, d.cmd, strconv.Itoa(d.n), d.stem, d.role
			key := strings.Join([]string{n, at, cmd, k}, "\t")
			if !seen[key] {
				mode = modeNew
			} else if seen[key+keyResent] && !seen[key+keyRechecked] {
				mode = modeAfter
			}
		}
		stemOf, isMarked := marked[n]
		if mode == noValue && !isMarked {
			continue
		}
		if !isMarked {
			stemOf = noValue
		}
		rows = append(rows, strings.Join([]string{idle[n], n, at, cmd, k, st, role, mode, stemOf}, "\t"))
	}
	return rows
}

// candidates is each idle agent with a delivery or a marker, in byte order, which is Python's code
// point order for UTF-8.
func candidates(idle map[string]string, newest map[string]delivery, marked map[string]string) []string {
	var out []string
	for n := range idle {
		_, d := newest[n]
		_, m := marked[n]
		if d || m {
			out = append(out, n)
		}
	}
	slices.Sort(out)
	return out
}

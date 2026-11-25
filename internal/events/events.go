// Package events is bin/lib/agents.sh's append_event, rule for rule: one line on
// PROJECT_DIR/.swarm/events.tsv for each command that changes state. It holds append_event's
// constants, EVENTS_LOG (LogFile), EVENT_SEP (Sep) and EVENT_VERSION (the version an Appender reads
// once). It also refuses the project SWARM_FORBID_PROJECT names, as hooks/lead-stop.sh's forbidden
// does; the worktree half of bin/swarm.sh's refusal stays the frame's.
package events

import (
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/plugin"
)

// LogFile is EVENTS_LOG, relative to PROJECT_DIR.
const LogFile = ".swarm/events.tsv"

// Sep is EVENT_SEP: what parts the outcome column's free text from its key=value tail.
const Sep = " ~~ "

// cut is Sep without its last space: an outcome that ends in it would read as the tail's Sep.
const cut = " ~~"

// manifest is the plugin.json the version= value is read from, relative to the plugin root.
const manifest = "/.claude-plugin/plugin.json"

// defaultOutcome is the outcome when the caller gives none, or an empty one.
const defaultOutcome = "ok"

// none stands for an empty target and for an unset or empty paneVar.
const none = "-"

// timeLayout is date -u +%Y-%m-%dT%H:%M:%SZ.
const timeLayout = "2006-01-02T15:04:05Z"

// paneVar names the actor's herdr pane, the line's fourth column.
const paneVar = "HERDR_PANE_ID"

// forbidVar names the checkout the tests run from, which an Appender never writes to.
const forbidVar = "SWARM_FORBID_PROJECT"

// columnBreaks is what becomes a space in every column, and what a left-out field's warning is cut
// at: tab, LF and CR.
const columnBreaks = "\t\n\r"

// fieldSpace is what bash's [[:space:]] matches in the C locale, as cmd/swarm/frame.go's fieldSpace:
// no field value, and no version, may hold one. Byte by byte, as in C: under a UTF-8 locale bash's
// match also refuses a value with bytes that are not UTF-8, or with a space such as U+00A0, which
// this keeps.
const fieldSpace = " \t\n\v\f\r"

// leftOut is the warning on a field that is left out, after its text cut at its first columnBreaks.
const leftOut = ": a field is key=value, the key [a-z_]+, the value not empty and with no whitespace"

// Appender appends lines to one project's events.tsv. Its zero value is not usable; make one with New.
type Appender struct {
	store   iface.Store
	project string    // PROJECT_DIR
	root    string    // the plugin root, the frame's SWARMDEV_HOME; empty reads /.claude-plugin/plugin.json
	stderr  io.Writer // where a left-out field's warning goes
	version string    // EVENT_VERSION: empty when the read failed or gave no version without whitespace
	read    bool      // EVENT_VERSION_READ: the version has been read
}

// New is an Appender for project, reading the version from root's plugin.json at its first append
// and warning on stderr.
func New(store iface.Store, project, root string, stderr io.Writer) *Appender {
	return &Appender{store: store, project: project, root: root, stderr: stderr}
}

// Append writes one line, as append_event <command> <target> [outcome] [key=value...] does, with the
// time now, which the caller reads (clock.Real() in production, as bash's date -u reads no test
// clock). The outcome is defaultOutcome when empty; its tab, LF and CR become spaces, and then, until
// neither is left, every Sep becomes a space, one trailing cut goes and trailing spaces go. A field
// that is not key=value, the key [a-z_]+ and the value with no fieldSpace, is left out with a warning
// on stderr; the line is still written. version= goes last. The columns are the time in UTC, the
// command, the target or none, paneVar or none, and the outcome with Sep and the tail when there is
// one, each with its columnBreaks made spaces. It returns AppendLine's error, writing nothing more on
// stderr, and takes no lock, as bash takes none. When forbidVar names the project, by physical path,
// it writes nothing, makes no folder and returns an error naming forbidVar.
func (a *Appender) Append(now time.Time, command, target, outcome string, fields ...string) error {
	if a.forbidden() {
		return errors.New(forbidVar + ": " + a.project + " is the checkout the tests run from; append_event writes nothing there")
	}
	if !a.read {
		a.read = true
		a.version = a.readVersion()
	}
	if a.version != "" {
		fields = append(slices.Clip(fields), "version="+a.version)
	}
	var kept []string
	for _, f := range fields {
		if isField(f) {
			kept = append(kept, f)
			continue
		}
		cutAt := f
		if i := strings.IndexAny(f, columnBreaks); i >= 0 {
			cutAt = f[:i]
		}
		_, _ = fmt.Fprintln(a.stderr, "append_event: left out "+cutAt+leftOut)
	}
	last := cleanOutcome(outcome)
	if len(kept) > 0 {
		last += Sep + strings.Join(kept, " ")
	}
	cols := []string{now.UTC().Format(timeLayout), command, orNone(target), orNone(os.Getenv(paneVar)), last}
	for i, c := range cols {
		cols[i] = breaksToSpaces(c)
	}
	return a.store.AppendLine(a.project+"/"+LogFile, strings.Join(cols, "\t"))
}

// forbidden is lead-stop.sh's forbidden: forbidVar is set, and its physical path and the project's
// both resolve and are the same.
func (a *Appender) forbidden() bool {
	dir := os.Getenv(forbidVar)
	if dir == "" {
		return false
	}
	f, err := a.store.RealPath(dir)
	if err != nil {
		return false
	}
	p, err := a.store.RealPath(a.project)
	return err == nil && p == f
}

// readVersion is the version= value: plugin.Version over root's plugin.json with every trailing LF
// stripped, as $( ) strips them, kept only when it is not empty and holds no fieldSpace. It is empty
// when the file cannot be read or holds no version.
func (a *Appender) readVersion() string {
	data, err := a.store.ReadFile(a.root + manifest)
	if err != nil {
		return ""
	}
	v, ok := plugin.Version(data)
	v = strings.TrimRight(v, "\n")
	if !ok || v == "" || strings.ContainsAny(v, fieldSpace) {
		return ""
	}
	return v
}

// cleanOutcome is the outcome column's free text, as append_event's loop leaves it.
func cleanOutcome(o string) string {
	if o == "" {
		o = defaultOutcome
	}
	o = breaksToSpaces(o)
	for strings.Contains(o, Sep) || strings.HasSuffix(o, cut) {
		o = strings.ReplaceAll(o, Sep, " ")
		o = strings.TrimSuffix(o, cut)
		o = strings.TrimRight(o, " ")
	}
	return o
}

// isField reports whether f matches ^[a-z_]+=[^[:space:]]+$, with [:space:] as fieldSpace. The key
// cannot hold =, so the match splits at the first one.
func isField(f string) bool {
	key, value, found := strings.Cut(f, "=")
	if !found || key == "" || value == "" || strings.ContainsAny(value, fieldSpace) {
		return false
	}
	for _, c := range []byte(key) {
		if (c < 'a' || c > 'z') && c != '_' {
			return false
		}
	}
	return true
}

// orNone is s, or none when s is empty.
func orNone(s string) string {
	if s == "" {
		return none
	}
	return s
}

// breaks makes each of columnBreaks a space, byte by byte, so text that is not UTF-8 keeps its bytes
// as bash keeps them.
var breaks = strings.NewReplacer("\t", " ", "\n", " ", "\r", " ")

// breaksToSpaces makes each of s's columnBreaks a space.
func breaksToSpaces(s string) string {
	return breaks.Replace(s)
}

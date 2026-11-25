package report

// report.py's gh runner (bin/lib/report.py:175-239,278-286): GH_SECONDS, GH_LIMIT, PASSES, SPENT, its
// gh with ERROR and LIMIT, and search_merged, over iface.CodeHost. Nothing runs them yet: until the
// switch, report.py's copy decides.

import (
	"context"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/clock"
	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/pyjson"
	"github.com/redscaresu/swarm-dev/internal/pytext"
)

// GHSeconds is how long one gh call may run before it is killed (GH_SECONDS).
const GHSeconds = 30

// GHLimit is the most merged PRs SearchMerged asks gh for (GH_LIMIT).
const GHLimit = 1000

// Passes matches a failure Call tries again: a reset connection, a cut answer, a timeout or a 5xx
// (PASSES). Python's re.IGNORECASE takes ı and İ for i, and its \d any decimal digit, where Go's (?i)
// and \d do not, so those are spelled out.
var Passes = regexp.MustCompile(`(?i)connect[iİı]on reset|unexpected EOF|[iİı]/o t[iİı]meout|TLS handshake t[iİı]meout|HTTP 5\p{Nd}\p{Nd}`)

// Spent matches gh's error once the hourly rate limit is spent (SPENT): no more calls this run.
var Spent = regexp.MustCompile(`API rate limit (already )?exceeded`)

// retryWaits are the seconds Call waits before each further try, before clock's scale; after the last
// failure it makes no more.
var retryWaits = []float64{1, 2}

// jsonFlag is where Call's call text stops: the fields gh is asked for are left out.
const jsonFlag = "--json"

// The words Error ends with, after the call text and ": ".
const (
	notTried   = "not tried: "
	unreadable = "an answer it could not read"
	notJSON    = "an answer that is not JSON"
	exitWord   = "exit "
)

// Parse says how Call reads gh's output, as report.py's gh's parse argument does.
type Parse int

const (
	// JSON is parse=json.loads: the output as strict UTF-8, read as JSON.
	JSON Parse = iota
	// Text is parse=str: the output as UTF-8 with each bad byte one U+FFFD, given as a string.
	Text
)

// GH is report.py's gh with its ERROR and LIMIT. One run shares one GH, as one flow run shares
// report.py's globals: once one section spends the hourly limit, the later ones make no calls either.
type GH struct {
	// Host runs gh.
	Host iface.CodeHost
	// Error is the last call that failed, and why (ERROR[0]). After a call that answered, it is
	// "<call>: an answer it could not read", for a caller that finds no list or object in the answer.
	Error string
	// Limit is gh's error once the hourly rate limit is spent (LIMIT[0]), or "" while it is not.
	Limit string
}

// Call runs gh with args, as report.py's gh does, killing it after seconds. It gives the answer as
// parse reads it, with \r\n and \r made \n: a pyjson value for JSON, a string for Text. It gives nil
// when gh fails, takes over seconds or answers what JSON cannot read, and Error says which call and
// why; like Python's None, nil is also the answer JSON null.
//
// A reset connection or a 5xx (Passes, searched over Error) is tried again 1 s and then 2 s later, as
// clock.Nap scales them; any other failure is not, as a secondary rate limit asks for a minute or more.
// Once the hourly limit is spent (Spent, on gh's last stderr line), this call and every later one fail
// at once with that error. A gh that cannot start, where Python's FileNotFoundError ends the run, and a
// scale clock refuses, where Python's float raises, end the call with nil.
func (g *GH) Call(seconds int, parse Parse, args ...string) any {
	call := callText(args)
	if g.Limit != "" {
		g.Error = call + ": " + notTried + g.Limit
		return nil
	}
	for try := 0; ; try++ {
		run := runBounded(g.Host, seconds, args)
		switch {
		case run.NoStart != nil:
			g.Error = call + ": " + run.NoStart.Error()
			return nil
		case run.CutShort:
			g.Error = call + ": over " + strconv.Itoa(seconds) + " s"
			return nil
		case returnCode(run) == 0:
			g.Error = call + ": " + unreadable
			return g.read(call, parse, run.Stdout)
		}
		line, ok := lastLine(pytext.DecodeReplace(run.Stderr))
		g.Error, g.Limit = call+": "+line, ""
		if !ok {
			g.Error = call + ": " + exitWord + strconv.Itoa(returnCode(run))
		} else if Spent.MatchString(line) {
			g.Limit = line
		}
		if try >= len(retryWaits) || !Passes.MatchString(g.Error) || clock.Nap(retryWaits[try]) != nil {
			return nil
		}
	}
}

// read gives out as parse reads it, setting Error when JSON cannot read it.
func (g *GH) read(call string, parse Parse, out []byte) any {
	if parse == Text {
		return textMode(pytext.DecodeReplace(out))
	}
	if !utf8.Valid(out) {
		g.Error = call + ": " + notJSON
		return nil
	}
	v, err := pyjson.Decode([]byte(textMode(string(out))))
	if err != nil {
		g.Error = call + ": " + notJSON
		return nil
	}
	return v
}

// SearchMerged is report.py's search_merged: the merged PRs of repo merged lo to hi (days, UTC), as
// gh pr list's JSON list of url, mergedAt, title, body and files, GHLimit at most, and false when gh
// fails, cannot start, takes over GHSeconds, writes stdout or stderr that is not UTF-8, or answers
// anything but a JSON list. It neither reads nor sets Error and Limit, and tries nothing again.
func (g *GH) SearchMerged(repo, lo, hi string) ([]any, bool) {
	run := runBounded(g.Host, GHSeconds, []string{"pr", "list", "-R", repo, "--state", "merged", "--limit", strconv.Itoa(GHLimit),
		"--json", "url,mergedAt,title,body,files", "--search", "merged:" + lo + ".." + hi})
	// Python's text mode decodes both streams before it looks at the exit code.
	if run.NoStart != nil || run.CutShort || !utf8.Valid(run.Stdout) || !utf8.Valid(run.Stderr) || returnCode(run) != 0 {
		return nil, false
	}
	v, err := pyjson.Decode([]byte(textMode(string(run.Stdout))))
	prs, ok := v.([]any)
	return prs, err == nil && ok
}

// runBounded runs gh with args through host, killed after seconds.
func runBounded(host iface.CodeHost, seconds int, args []string) iface.GhResult {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(seconds)*time.Second)
	defer cancel()
	return host.Run(ctx, args...)
}

// callText is the call Error names: "gh" and args up to the first --json, joined by spaces.
func callText(args []string) string {
	if i := slices.Index(args, jsonFlag); i >= 0 {
		args = args[:i]
	}
	return strings.Join(append([]string{"gh"}, args...), " ")
}

// returnCode is Python's returncode for a gh that ran: its exit code, or minus the signal that killed
// it.
func returnCode(run iface.GhResult) int {
	if run.Signal != 0 {
		return -run.Signal
	}
	return run.Exit
}

// textMode makes \r\n and \r into \n, as Python's text mode reads newlines.
func textMode(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
}

// lineBreaks are the breaks Python's str.splitlines splits at; \r\n is one break, which splitting at
// \r and then \n gives too, since the empty line between is dropped.
const lineBreaks = "\n\r\v\f\x1c\x1d\x1e\u0085\u2028\u2029"

// lastLine is the last of s's lines that is not empty once stripped, stripped, as report.py's
// [l.strip() for l in s.splitlines() if l.strip()][-1] gives it, and false when there is none.
func lastLine(s string) (string, bool) {
	lines := strings.FieldsFunc(s, func(r rune) bool { return strings.ContainsRune(lineBreaks, r) })
	for i := len(lines) - 1; i >= 0; i-- {
		if l := strings.TrimFunc(lines[i], pySpace); l != "" {
			return l, true
		}
	}
	return "", false
}

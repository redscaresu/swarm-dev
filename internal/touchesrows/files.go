package touchesrows

// The file readers of bin/lib/touches_rows.py: a story's front matter under its state file (front),
// its touches entries (entries) and events.tsv's ok lines (ok_events). Each reads through the store,
// and files_compare_test.go runs both copies over the same board and events files.

import (
	"errors"
	"io/fs"
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/eventsoutcome"
	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/pytext"
)

// baseSuffix ends a state file key that holds the value the story file had when swarm.sh wrote the
// key (state_set's <key>@base).
const baseSuffix = "@base"

// storyExt is the length, in characters, of the .md a story file's name ends in, which its state
// file's name drops.
const storyExt = 3

// readText is path's text as Python's open(path, encoding="utf-8", errors="replace").read() gives
// it: bad UTF-8 replaced, then each \r\n and each lone \r read as \n, as text mode's universal
// newlines do. The error is the store's.
func readText(st iface.Store, path string) (string, error) {
	b, err := st.ReadFile(path)
	if err != nil {
		return "", err
	}
	text := strings.ReplaceAll(pytext.DecodeReplace(b), "\r\n", "\n")
	return strings.ReplaceAll(text, "\r", "\n"), nil
}

// pyBasename is os.path.basename: the text after path's last /, "" for a path that ends in one.
func pyBasename(path string) string {
	return path[strings.LastIndex(path, "/")+1:]
}

// pyJoin is os.path.join(a, b): b alone when it starts with /, else a and b with one / between,
// none added after an a that is empty or ends in /, and nothing cleaned.
func pyJoin(a, b string) string {
	switch {
	case strings.HasPrefix(b, "/"):
		return b
	case a == "" || strings.HasSuffix(a, "/"):
		return a + b
	}
	return a + "/" + b
}

// dropChars is s without its last n characters, as Python's s[:-n] slices a str: a byte that is
// not UTF-8 counts as one, as it does in a path Python decoded with surrogateescape. "" when s has
// n characters or fewer.
func dropChars(s string, n int) string {
	for i := 0; i < n && s != ""; i++ {
		_, size := utf8.DecodeLastRuneInString(s)
		s = s[:len(s)-size]
	}
	return s
}

// Front is a story's or an epic's front matter (FrontText of the file at path) under what swarm.sh
// wrote to its state file (state_set): stateDir's file named as path's file without its .md. A
// state value wins unless the state file also has the key's <key>@base and that differs from the
// file's value, so an edit to the file after the state line wins. The values are compared as
// written, as state_value compares them, and only then trimmed of the spaces Python's str.strip()
// takes. A missing state file adds nothing. stateDir is the board's state folder (the stories'),
// or its epics folder for an epic; Python's front falls back to a global only its __main__ sets,
// so the Go takes it always. The error is the store's, for path itself or for a state file that is
// there but cannot be read, where Python raises.
func Front(st iface.Store, path, stateDir string) (map[string]string, error) {
	text, err := readText(st, path)
	if err != nil {
		return nil, err
	}
	out := FrontText(text)
	stateText, err := readText(st, pyJoin(stateDir, dropChars(pyBasename(path), storyExt)))
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	state := map[string]string{}
	Pairs(strings.Split(stateText, "\n"), state)
	for k, v := range state {
		if strings.HasSuffix(k, baseSuffix) {
			continue
		}
		base, ok := state[k+baseSuffix]
		if !ok || base == out[k] {
			out[k] = v
		}
	}
	for k, v := range out {
		out[k] = strings.TrimFunc(v, isSpace)
	}
	return out, nil
}

// repoPrefix is a touches part that names its repo: a name of letters, digits, ., _ and -, then
// ": ", then the rest of the line. Python's re.match anchors it at the start, and its . stops at a
// newline, as Go's does.
var repoPrefix = regexp.MustCompile(`^([A-Za-z0-9._-]+): (.*)`)

// splitTouches is touches' raw text cut at each comma outside parentheses, as entries does: the
// parentheses and everything inside them dropped, and a ) with no ( before it read as none.
func splitTouches(raw string) []string {
	var parts []string
	var cur strings.Builder
	depth := 0
	for i := 0; i < len(raw); i++ { // bytes: the three that matter are ASCII, inside no other character
		switch c := raw[i]; {
		case c == '(':
			depth++
		case c == ')':
			depth = max(depth-1, 0)
		case depth == 0 && c == ',':
			parts = append(parts, cur.String())
			cur.Reset()
		case depth == 0:
			cur.WriteByte(c)
		}
	}
	return append(parts, cur.String())
}

// Entries is the (repo, file, part) of each entry in fm's touches, as entries does. The list's
// brackets and the spaces around it go, and it is cut at each comma outside parentheses. A part may
// start with a repo prefix (repo: file), else its repo is fm's repo. A part whose text before its
// first colon has no / and no ., and is no file in its repo's checkout, is a further part of the
// entry before: it keeps that entry's file, and its repo unless it has a prefix of its own. So
// Makefile:lint is a file only where the checkout has a Makefile. The checkout is projectDir for
// no repo or the project's own name (projectDir's last name), else the repo's folder under reposDir.
// A repo that is the project's own name is "". An empty part is skipped.
func Entries(st iface.Store, fm map[string]string, projectDir, reposDir string) []Entry {
	repo, project := fm["repo"], pyBasename(projectDir)
	raw := strings.Trim(strings.TrimFunc(fm["touches"], isSpace), "[]")
	var out []Entry
	norm := func(r string) string {
		if r == project {
			return ""
		}
		return r
	}
	for _, p := range splitTouches(raw) {
		p = strings.TrimFunc(p, isSpace)
		prefix, hasPrefix := "", false
		if m := repoPrefix.FindStringSubmatch(p); m != nil {
			prefix, hasPrefix, p = m[1], true, strings.TrimFunc(m[2], isSpace)
		}
		if p == "" {
			continue
		}
		head, _, _ := strings.Cut(p, ":")
		head = strings.TrimFunc(head, isSpace)
		fileRepo := repo
		if hasPrefix {
			fileRepo = prefix
		}
		if len(out) > 0 && !strings.ContainsAny(head, "/.") && !st.IsFile(pyJoin(checkout(fileRepo, project, projectDir, reposDir), head)) {
			last := out[len(out)-1]
			r := last.Repo
			if hasPrefix {
				r = prefix
			}
			out = append(out, Entry{Repo: norm(r), File: last.File, Part: p})
			continue
		}
		f, fn, _ := strings.Cut(p, ":")
		out = append(out, Entry{Repo: norm(fileRepo), File: strings.TrimFunc(f, isSpace), Part: strings.TrimFunc(fn, isSpace)})
	}
	return out
}

// checkout is the folder a touches file of repo r lives in: projectDir for no repo or the
// project's own name, else r's folder under reposDir.
func checkout(r, project, projectDir, reposDir string) string {
	if r == "" || r == project {
		return projectDir
	}
	return pyJoin(reposDir, r)
}

// EventKey is an events.tsv line's command (row[1]) and target (row[2]).
type EventKey struct {
	Command, Target string
}

// eventCols is the number of columns an events.tsv line has: time, command, target, agent and
// outcome.
const eventCols = 5

// okOutcome is the outcome of a line that succeeded, alone or followed by okDetail and more.
const (
	okOutcome = "ok"
	okDetail  = "ok ("
)

// OkEvents is the time of each ok line in the events.tsv at path, by command and target, in file
// order, as ok_events gives it: the line's UTC time in seconds since the epoch, plus its place in
// the file (its index over the file's line count, the empty one after a last newline counted) so
// two lines in one second keep their order. A line is ok when it has exactly five tab-separated
// columns and its outcome, without its tail, is ok or starts with "ok (". A line whose time
// parseTime refuses is skipped. A missing file gives an empty map; the error is the store's for a
// file that is there but cannot be read, where Python raises.
func OkEvents(st iface.Store, path string) (map[EventKey][]float64, error) {
	out := map[EventKey][]float64{}
	text, err := readText(st, path)
	if errors.Is(err, fs.ErrNotExist) {
		return out, nil
	}
	if err != nil {
		return nil, err
	}
	lines := strings.Split(text, "\n")
	for i, l := range lines {
		e := strings.Split(l, "\t")
		o := eventsoutcome.Outcome(e)
		if len(e) != eventCols || o != okOutcome && !strings.HasPrefix(o, okDetail) {
			continue
		}
		secs, ok := parseTime(e[0])
		if !ok {
			continue
		}
		k := EventKey{Command: e[1], Target: e[2]}
		out[k] = append(out[k], float64(secs)+float64(i)/float64(len(lines)))
	}
	return out, nil
}

// fieldChar is a class one character of a time field may be in: an ASCII digit from lo to hi, any
// Unicode decimal digit (as Python's \d is, for str), or a space.
type fieldChar struct {
	lo, hi       rune
	digit, space bool
}

func ascii(lo, hi rune) fieldChar { return fieldChar{lo: lo, hi: hi} }

var (
	anyDigit = fieldChar{digit: true}
	space    = fieldChar{space: true}
)

// in reports whether r is in class c.
func (c fieldChar) in(r rune) bool {
	switch {
	case c.digit:
		return unicode.IsDigit(r)
	case c.space:
		return r == ' '
	}
	return r >= c.lo && r <= c.hi
}

// Each time field's alternatives in Python 3.14's _strptime.TimeRE, one class per character, for
// the format %Y-%m-%dT%H:%M:%SZ (checked 2026-11-25). Python 3.14 takes a space before a one-digit
// hour; an older Python may not, so the comparison test has no such case.
var (
	fieldY = [][]fieldChar{{anyDigit, anyDigit, anyDigit, anyDigit}}
	fieldm = [][]fieldChar{{ascii('1', '1'), ascii('0', '2')}, {ascii('0', '0'), ascii('1', '9')}, {ascii('1', '9')}}
	fieldd = [][]fieldChar{{ascii('3', '3'), ascii('0', '1')}, {ascii('1', '2'), anyDigit}, {ascii('0', '0'), ascii('1', '9')},
		{ascii('1', '9')}, {space, ascii('1', '9')}}
	fieldH = [][]fieldChar{{ascii('2', '2'), ascii('0', '3')}, {ascii('0', '1'), anyDigit}, {anyDigit}, {space, anyDigit}}
	fieldM = [][]fieldChar{{ascii('0', '5'), anyDigit}, {anyDigit}}
	fieldS = [][]fieldChar{{ascii('6', '6'), ascii('0', '1')}, {ascii('0', '5'), anyDigit}, {anyDigit}}
)

// decimalBase is the base a time field's digits are read in, and the length of each run of digits
// in Unicode's Nd table.
const decimalBase = 10

// digitValue is r's value as a decimal digit, as Python's int() reads it: its place in its run of
// ten in Unicode's Nd table, each run of which starts at a zero.
func digitValue(r rune) int {
	for _, rg := range unicode.Nd.R16 {
		if r >= rune(rg.Lo) && r <= rune(rg.Hi) {
			return int(r-rune(rg.Lo)) % decimalBase
		}
	}
	for _, rg := range unicode.Nd.R32 {
		if r >= rune(rg.Lo) && r <= rune(rg.Hi) {
			return int(r-rune(rg.Lo)) % decimalBase
		}
	}
	return 0
}

// field reads one time field: its value when s, every character, matches one of alts, as
// int(found) reads it (a space ignored).
func field(s string, alts [][]fieldChar) (int, bool) {
	rs := []rune(s)
	for _, alt := range alts {
		if len(alt) != len(rs) {
			continue
		}
		v, ok := 0, true
		for i, c := range alt {
			if ok = c.in(rs[i]); !ok {
				break
			}
			if c.space {
				continue
			}
			v = v*decimalBase + digitValue(rs[i])
		}
		if ok {
			return v, true
		}
	}
	return 0, false
}

// timeSeps are the literal characters between the fields of %Y-%m-%dT%H:%M:%SZ, the last ending
// the text. _strptime matches them in any case.
var timeSeps = []rune{'-', '-', 'T', ':', ':', 'Z'}

// timeFields are the fields before each of timeSeps.
var timeFields = [][][]fieldChar{fieldY, fieldm, fieldd, fieldH, fieldM, fieldS}

// Seconds in a minute and in an hour, which calendar.timegm adds up.
const (
	minuteSecs = 60
	hourSecs   = 60 * minuteSecs
)

// parseTime is calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ")), and false where strptime
// raises. A field holds only the digits that strptime's pattern for it takes, Unicode decimal
// digits where it says \d; a separator matches in either case; nothing may follow the Z. The date
// must exist (year 1 to 9999, a day its month has); the seconds may be 60 or 61, which carry into
// the next minute as timegm adds them.
func parseTime(s string) (int64, bool) {
	vals := make([]int, len(timeFields))
	rest := s
	for i, sep := range timeSeps {
		at := strings.IndexFunc(rest, func(r rune) bool { return unicode.ToUpper(r) == sep })
		if at < 0 {
			return 0, false
		}
		v, ok := field(rest[:at], timeFields[i])
		if !ok {
			return 0, false
		}
		vals[i] = v
		rest = rest[at+utf8.RuneLen(sep):]
	}
	if rest != "" {
		return 0, false
	}
	year, month, day := vals[0], time.Month(vals[1]), vals[2]
	date := time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
	if year < 1 || date.Day() != day {
		return 0, false
	}
	return date.Unix() + int64(vals[3]*hourSecs+vals[4]*minuteSecs+vals[5]), true
}

package report

import (
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// The text rules of bin/lib/report.py (pr_key, STEP_UP, escalate_build, AGENT_NAME_MAX, agent_name,
// cut_records, PHASES, CONTROL, merge_time and local_day). Python works on code points, and its \s,
// \d, strip() and lower() are Unicode-wide, where Go's regexp \s and \d are ASCII. So the rules here
// read their input by rune, as valid UTF-8 (a byte that is not is one U+FFFD, which Python's str never
// holds), through pySpace, pyDigit and pyLower. Unicode's tables differ by version (Go's unicode.Version
// against Python's unicodedata.unidata_version), so a code point one of them does not know may differ.

// AgentNameMax is bash's AGENT_NAME_MAX: herdr's name for an agent is cut to this many characters.
const AgentNameMax = 32

// Phases are the phases outcomes splits a build's start-to-merge minutes into, in the order its
// columns print (<phase>_min); flow's time_in_state reads them by these names. Each call returns a
// fresh slice.
func Phases() []string {
	return []string{"building", "ci", "review_wait", "fixing", "merge_wait"}
}

// Control matches a C0 or C1 control character, or DEL: gh's errors and a fork's job names are not
// ours to print raw, so callers replace each match with nothing. RE2 reads \x9f in a pattern as the
// code point U+009F, as Python's re does.
var Control = regexp.MustCompile(`[\x00-\x1f\x7f-\x9f]`)

// The literals PRKey and the step-up rules read.
const (
	githubHost   = "github.com/"
	pullPath     = "/pull/"
	stepUpPrefix = "ok ("
	stepUpColon  = ": "
	stepUpArrow  = " -> "
	attemptStart = "ok (attempt "
	closeParen   = ")"
)

// pySpace reports whether Python's str.isspace, and so its \s and strip(), takes r: Unicode's
// White_Space, as unicode.IsSpace has it, and the four separators U+001C to U+001F, which Python
// counts by their bidirectional class.
func pySpace(r rune) bool {
	return unicode.IsSpace(r) || r >= 0x1c && r <= 0x1f
}

// pyDigit reports whether Python's \d takes r: any decimal digit (category Nd), not only 0 to 9.
func pyDigit(r rune) bool {
	return unicode.IsDigit(r)
}

// span is the byte length of s's longest prefix whose runes all satisfy ok.
func span(s string, ok func(rune) bool) int {
	for i, r := range s {
		if !ok(r) {
			return i
		}
	}
	return len(s)
}

// all reports whether s is not empty and every rune in it satisfies ok.
func all(s string, ok func(rune) bool) bool {
	return s != "" && span(s, ok) == len(s)
}

// PRKey is report.py's pr_key: a PR's key as owner/repo#N with owner/repo lowercased, from the first
// github.com/<owner>/<repo>/pull/<N> in pr, else from a pr that is all owner/repo#N, with spaces
// around it. Any other pr is kept, with its spaces and its trailing slashes cut. N keeps its digits as
// written, any decimal digits Python's \d takes.
func PRKey(pr string) string {
	if repo, n, ok := prURL(pr); ok {
		return pyLower(repo) + "#" + n
	}
	if repo, n, ok := prRef(pr); ok {
		return pyLower(repo) + "#" + n
	}
	return strings.TrimRight(strings.TrimFunc(pr, pySpace), "/")
}

// notSlashOrSpace is [^/\s]: a part of owner/repo in a PR's URL.
func notSlashOrSpace(r rune) bool {
	return r != '/' && !pySpace(r)
}

// notSlashSpaceOrHash is [^/\s#]: a part of owner/repo in owner/repo#N.
func notSlashSpaceOrHash(r rune) bool {
	return notSlashOrSpace(r) && r != '#'
}

// ownerRepo reads <owner>/<repo> from the start of s, each part a non-empty run of runes that part
// takes, and returns it and the rest of s.
func ownerRepo(s string, part func(rune) bool) (repo, rest string, ok bool) {
	owner := span(s, part)
	if owner == 0 || !strings.HasPrefix(s[owner:], "/") {
		return "", "", false
	}
	name := span(s[owner+1:], part)
	if name == 0 {
		return "", "", false
	}
	end := owner + 1 + name
	return s[:end], s[end:], true
}

// prURL is re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)"): each part can hold no slash, so at
// each github.com/ there is one way to match, and the first that matches wins.
func prURL(pr string) (repo, n string, ok bool) {
	for i := strings.Index(pr, githubHost); i >= 0; {
		at := i + len(githubHost)
		if repo, rest, ok := ownerRepo(pr[at:], notSlashOrSpace); ok {
			if rest, ok := strings.CutPrefix(rest, pullPath); ok {
				if d := span(rest, pyDigit); d > 0 {
					return repo, rest[:d], true
				}
			}
		}
		next := strings.Index(pr[i+1:], githubHost)
		if next < 0 {
			break
		}
		i += 1 + next
	}
	return "", "", false
}

// prRef is re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*"): no part can hold a space, so the spaces
// at each end are all the spaces there are.
func prRef(pr string) (repo, n string, ok bool) {
	s := strings.TrimLeftFunc(pr, pySpace)
	repo, rest, ok := ownerRepo(s, notSlashSpaceOrHash)
	if !ok {
		return "", "", false
	}
	rest, ok = strings.CutPrefix(rest, "#")
	if !ok {
		return "", "", false
	}
	d := span(rest, pyDigit)
	if d == 0 || strings.TrimLeftFunc(rest[d:], pySpace) != "" {
		return "", "", false
	}
	return repo, rest[:d], true
}

// The two code points Python's lower() maps by more than unicode.ToLower's simple mapping.
const (
	dottedCapitalI = 'İ' // U+0130, which lowers to i and U+0307 (Unicode's SpecialCasing)
	capitalSigma   = 'Σ' // U+03A3, which lowers to ς at a word's end and σ elsewhere
)

// pyLower is Python's str.lower(): each code point's simple lowercase, but İ gives i and U+0307,
// and Σ gives ς in Final_Sigma's context (finalSigma).
func pyLower(s string) string {
	runes := []rune(s)
	var b strings.Builder
	for i, r := range runes {
		switch {
		case r == dottedCapitalI:
			b.WriteString("i\u0307")
		case r == capitalSigma && finalSigma(runes, i):
			b.WriteRune('ς')
		default:
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return b.String()
}

// finalSigma is CPython's handle_capital_sigma: the Σ at runes[i] ends a word when a cased letter
// comes before it and none after it, skipping case-ignorable code points both ways.
func finalSigma(runes []rune, i int) bool {
	j := i - 1
	for j >= 0 && caseIgnorable(runes[j]) {
		j--
	}
	if j < 0 || !cased(runes[j]) {
		return false
	}
	j = i + 1
	for j < len(runes) && caseIgnorable(runes[j]) {
		j++
	}
	return j == len(runes) || !cased(runes[j])
}

// cased is Unicode's Cased property: Lowercase, Uppercase or titlecase.
func cased(r rune) bool {
	return unicode.In(r, unicode.Ll, unicode.Lu, unicode.Lt, unicode.Other_Lowercase, unicode.Other_Uppercase)
}

// wordBreakMid is Unicode's Word_Break values MidLetter, MidNumLet and Single_Quote, the part of
// Case_Ignorable that is no general category. Go's unicode package has no Word_Break table.
var wordBreakMid = []rune{
	'\'', '.', ':', 0xb7, 0x387, 0x55f, 0x5f4, 0x2018, 0x2019, 0x2024, 0x2027, 0xfe13, 0xfe52,
	0xfe55, 0xff07, 0xff0e, 0xff1a,
}

// caseIgnorable is Unicode's Case_Ignorable property: nonspacing and enclosing marks, format
// characters, modifier letters and symbols, and wordBreakMid.
func caseIgnorable(r rune) bool {
	if unicode.In(r, unicode.Mn, unicode.Me, unicode.Cf, unicode.Lm, unicode.Sk) {
		return true
	}
	for _, m := range wordBreakMid {
		if r == m {
			return true
		}
	}
	return false
}

// StepUp is report.py's STEP_UP.fullmatch: a step-up's escalate line, ok (<trigger>: <from> -> <to>),
// with trigger of [a-z0-9-] and from and to of no spaces. to may hold a ), as \S takes one.
func StepUp(result string) (trigger, from, to string, ok bool) {
	rest, ok := strings.CutPrefix(result, stepUpPrefix)
	if !ok {
		return "", "", "", false
	}
	t := span(rest, triggerRune)
	if t == 0 {
		return "", "", "", false
	}
	trigger, rest = rest[:t], rest[t:]
	if rest, ok = strings.CutPrefix(rest, stepUpColon); !ok {
		return "", "", "", false
	}
	f := span(rest, notSpace)
	from, rest = rest[:f], rest[f:]
	if rest, ok = strings.CutPrefix(rest, stepUpArrow); !ok || f == 0 {
		return "", "", "", false
	}
	to, ok = strings.CutSuffix(rest, closeParen)
	if !ok || !all(to, notSpace) {
		return "", "", "", false
	}
	return trigger, from, to, true
}

// triggerRune is [a-z0-9-], a step-up trigger's alphabet.
func triggerRune(r rune) bool {
	return r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '-'
}

// notSpace is Python's \S.
func notSpace(r rune) bool {
	return !pySpace(r)
}

// EscalateBuild is report.py's escalate_build: whether an escalate line started an escalate build on
// model (the escalate role's): build_story's ok (attempt N), or a step-up to model. A step-up to a
// lower rung started none.
func EscalateBuild(result, model string) bool {
	if n, ok := strings.CutPrefix(result, attemptStart); ok {
		if d, ok := strings.CutSuffix(n, closeParen); ok && all(d, pyDigit) {
			return true
		}
	}
	_, _, to, ok := StepUp(result)
	return ok && to == model
}

// AgentName is report.py's agent_name: the name agents.tsv keeps for a slug. It lowercases n as
// Python does (pyLower), makes each code point outside [a-z0-9_-] one dash, puts an s first when the
// name does not start with a letter, and cuts it to AgentNameMax. It works per code point, so é gives
// one dash, İ gives i and a dash, and the Kelvin sign gives k. bash's agent_name works per byte, which
// is not this rule.
func AgentName(n string) string {
	var b strings.Builder
	for _, r := range pyLower(n) {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}
	name := b.String()
	if name == "" || name[0] < 'a' || name[0] > 'z' {
		name = "s" + name
	}
	if len(name) > AgentNameMax { // every rune is ASCII by now, so bytes are code points
		name = name[:AgentNameMax]
	}
	return name
}

// CutRecords is report.py's cut_records: each agent name to the one full name in names that AgentName
// gives it. A name two or more full names share maps to "", where Python has None, since herdr's name
// then never says whose it is. Its one caller reads both as no record (cuts.get(n) or n). A name
// AgentNameMax long may be a cut, so names are only names known to be full.
func CutRecords(names []string) map[string]string {
	by := map[string]string{}
	seen := map[string]bool{}
	for _, n := range names {
		if seen[n] {
			continue
		}
		seen[n] = true
		c := AgentName(n)
		if _, shared := by[c]; shared {
			by[c] = ""
		} else {
			by[c] = n
		}
	}
	return by
}

// The forms MergeTime reads.
const (
	dateLen   = len("YYYY-MM-DD")
	maxOffset = 24 * 60 * 60 // seconds; Python's timezone takes an offset strictly inside a day
)

// MergeTime is report.py's merge_time: gh's mergedAt as an aware time, or false when it is empty,
// malformed or has no offset. Like Python, it reads every Z as +00:00 first. It reads the forms every
// supported python3's datetime.fromisoformat reads alike: YYYY-MM-DD, any one character,
// HH[:MM[:SS[.fff|.ffffff]]], then ±HH:MM[:SS] under a day. It refuses what only some reads accept,
// or what Go's zones cannot hold: the forms Python 3.11 added, 24:00, a fraction of minutes (3.12
// reads 10:00.5, 3.14 does not), an offset's minutes or seconds over 59 (some patch releases read
// +00:99 as 99 minutes), one stray character before the offset, and an offset with a fraction of a
// second.
func MergeTime(t string) (time.Time, bool) {
	s := strings.ReplaceAll(t, "Z", "+00:00")
	if len(s) <= dateLen {
		return time.Time{}, false // a date alone is naive, so Python's merge_time gives None too
	}
	year, month, day, ok := isoDate(s[:dateLen])
	_, sepLen := utf8.DecodeRuneInString(s[dateLen:])
	rest := s[dateLen+sepLen:]
	at := strings.IndexAny(rest, "+-")
	if !ok || at < 0 {
		return time.Time{}, false
	}
	hour, minute, second, micro, ok := isoClock(rest[:at])
	if !ok || !validDate(year, month, day) || hour > 23 || minute > 59 || second > 59 {
		return time.Time{}, false
	}
	offset, ok := isoOffset(rest[at:])
	if !ok {
		return time.Time{}, false
	}
	zone := time.UTC
	if offset != 0 {
		zone = time.FixedZone("", offset)
	}
	return time.Date(year, time.Month(month), day, hour, minute, second, micro*int(time.Microsecond), zone), true
}

// digits is s as a whole number when it is all ASCII digits, as CPython's parse_digits reads them.
func digits(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return 0, false
		}
		n = n*10 + int(s[i]-'0')
	}
	return n, true
}

// isoDate reads YYYY-MM-DD.
func isoDate(s string) (year, month, day int, ok bool) {
	if s[4] != '-' || s[7] != '-' {
		return 0, 0, 0, false
	}
	year, ok1 := digits(s[:4])
	month, ok2 := digits(s[5:7])
	day, ok3 := digits(s[8:])
	return year, month, day, ok1 && ok2 && ok3
}

// validDate reports whether Python's datetime takes the day: year 1 to 9999, a real month and day.
func validDate(year, month, day int) bool {
	if year < 1 || month < 1 || month > 12 || day < 1 {
		return false
	}
	return time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC).Day() == day
}

// twoDigitFields reads s as fields of two ASCII digits each, split at colons, between lo and hi
// of them.
func twoDigitFields(s string, lo, hi int) ([]int, bool) {
	fields := strings.Split(s, ":")
	if len(fields) < lo || len(fields) > hi {
		return nil, false
	}
	out := make([]int, 0, len(fields))
	for _, f := range fields {
		n, ok := digits(f)
		if !ok || len(f) != 2 {
			return nil, false
		}
		out = append(out, n)
	}
	return out, true
}

// isoClock reads HH[:MM[:SS[.fff|.ffffff]]], which every supported fromisoformat reads alike.
func isoClock(s string) (hour, minute, second, micro int, ok bool) {
	whole, frac, hasFrac := strings.Cut(s, ".")
	parts, ok := twoDigitFields(whole, 1, 3)
	if !ok {
		return 0, 0, 0, 0, false
	}
	withSeconds := len(parts) == 3
	parts = append(parts, 0, 0)[:3]
	if hasFrac {
		n, ok := digits(frac)
		switch {
		case !ok || !withSeconds: // a fraction only of seconds
			return 0, 0, 0, 0, false
		case len(frac) == 3:
			micro = n * 1000
		case len(frac) == 6:
			micro = n
		default:
			return 0, 0, 0, 0, false
		}
	}
	return parts[0], parts[1], parts[2], micro, true
}

// isoOffset reads ±HH:MM[:SS] as seconds east of UTC, under a day either way, with MM and SS at most
// 59.
func isoOffset(s string) (int, bool) {
	parts, ok := twoDigitFields(s[1:], 2, 3)
	if !ok {
		return 0, false
	}
	parts = append(parts, 0)[:3]
	total := parts[0]*3600 + parts[1]*60 + parts[2]
	if parts[1] > 59 || parts[2] > 59 || total >= maxOffset {
		return 0, false
	}
	if s[0] == '-' {
		return -total, true
	}
	return total, true
}

// LocalDay is report.py's local_day: an aware time's calendar day in time.Local, held at midnight in
// UTC as clock.Today holds its day, so two days differ by whole multiples of 24 hours. log-finding
// dates findings in local time, so rework counts days so.
func LocalDay(t time.Time) time.Time {
	y, m, d := t.In(time.Local).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

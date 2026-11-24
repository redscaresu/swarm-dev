package report

import (
	"strings"
	"unicode"
)

// fixReach is report.py's FIX_REACH: the most characters (code points, as Python counts them) from
// the end of a fix verb to the PR it fixes.
const fixReach = 40

// A pattern is a run of groups, each a list of literal alternatives tried in order, as Python's re
// backtracks through them; "" is an optional group's empty choice. Every match of one starts and ends
// on a word boundary (\b).
type pattern [][]string

// notAFix is report.py's NOT_A_FIX: a clause that names an earlier PR without fixing it.
var notAFix = []pattern{{{"merge after", "depends on", "stacked on", "merged origin/main"}}}

// fixVerbs is report.py's FIX, its alternatives in its order: a fix verb with an optional hot, bug or
// quick prefix (hyphen or not), rework of, and regression from, in or of.
var fixVerbs = []pattern{
	{{"hot-", "hot", "bug-", "bug", "quick-", "quick", ""}, {"fix"}, {"es", "ed", "ing", ""}},
	{{"rework of"}},
	{{"regression "}, {"from", "in", "of"}},
}

// negations are NEGATED's words that need a word boundary before them; negatedSuffix needs none.
var negations = []string{"not", "never", "no longer"}

const negatedSuffix = "n't"

// The characters CLAUSE's lookbehind (?<=[.!?]) and pr_ref's (?<![\w./-]) and (?<![\w/#]) take, beside \w.
const (
	sentenceEnds  = ".!?"
	notBeforeRepo = "./-"
	notBeforeBare = "/#"
)

// isWord is Python's Unicode \w: a letter, a number or an underscore, where RE2's \w is ASCII only.
func isWord(r rune) bool { return r == '_' || unicode.IsLetter(r) || unicode.IsNumber(r) }

// isSpace is Python's Unicode \s: Go's white space and the four separators \x1c to \x1f.
func isSpace(r rune) bool { return unicode.IsSpace(r) || (r >= '\x1c' && r <= '\x1f') }

// isDigit is Python's Unicode \d, a decimal digit of any script.
func isDigit(r rune) bool { return unicode.IsDigit(r) }

// foldExtra holds the two letters Python's re.I takes as an ASCII letter beside those whose lower case
// it is (İ and the Kelvin sign): dotless ı as i, and long ſ as s.
var foldExtra = map[rune]rune{'ı': 'i', 'ſ': 's'}

// foldEq is whether re.I matches text rune t with pattern rune p. It is exact for the ASCII a
// pattern here holds; a non-ASCII rune of a repo name is matched by its lower case alone.
func foldEq(t, p rune) bool {
	lt, lp := unicode.ToLower(t), unicode.ToLower(p)
	if e, ok := foldExtra[t]; ok {
		lt = e
	}
	return lt == lp
}

// boundary is Python's \b at i in rs: a word rune on one side and not the other, past an end not one.
func boundary(rs []rune, i int) bool {
	return (i > 0 && isWord(rs[i-1])) != (i < len(rs) && isWord(rs[i]))
}

// literalAt is the end of lit matched with re.I at i in rs, and whether it matched.
func literalAt(rs []rune, i int, lit string) (int, bool) {
	for _, p := range lit {
		if i >= len(rs) || !foldEq(rs[i], p) {
			return i, false
		}
		i++
	}
	return i, true
}

// patternAt is the end of the first way pat matches at i and ends on a word boundary, as Python's
// backtracking finds it, and whether one does.
func patternAt(rs []rune, i int, pat pattern) (int, bool) {
	if len(pat) == 0 {
		return i, boundary(rs, i)
	}
	for _, alt := range pat[0] {
		if j, ok := literalAt(rs, i, alt); ok {
			if end, ok := patternAt(rs, j, pat[1:]); ok {
				return end, true
			}
		}
	}
	return i, false
}

// span is one match: rs[start:end].
type span struct{ start, end int }

// findAll is finditer over rs for \b(?:pats...)\b: the leftmost matches, each search going on from
// the end of the last match.
func findAll(rs []rune, pats []pattern) []span {
	var out []span
	for i := 0; i < len(rs); i++ {
		if !boundary(rs, i) {
			continue
		}
		for _, pat := range pats {
			if end, ok := patternAt(rs, i, pat); ok {
				out = append(out, span{i, end})
				i = end - 1
				break
			}
		}
	}
	return out
}

// clauses is CLAUSE.split: rs cut at a run of white space after a sentence end, a semicolon or a
// line break, empty clauses kept.
func clauses(rs []rune) [][]rune {
	var out [][]rune
	start := 0
	for i := 0; i < len(rs); {
		end := i + 1
		switch {
		case i > 0 && strings.ContainsRune(sentenceEnds, rs[i-1]) && isSpace(rs[i]):
			for end < len(rs) && isSpace(rs[end]) {
				end++
			}
		case rs[i] == ';' || rs[i] == '\n':
		default:
			i++
			continue
		}
		out = append(out, rs[start:i])
		start, i = end, end
	}
	return append(out, rs[start:])
}

// trimRight is rs with its run of trailing runes that keep satisfies cut off.
func trimRight(rs []rune, keep func(rune) bool) []rune {
	i := len(rs)
	for i > 0 && keep(rs[i-1]) {
		i--
	}
	return rs[:i]
}

// endsWith is whether rs ends with lit, matched with re.I, and where lit starts in rs when it does.
func endsWith(rs []rune, lit string) (int, bool) {
	i := len(rs) - len([]rune(lit))
	if i < 0 {
		return i, false
	}
	_, ok := literalAt(rs, i, lit)
	return i, ok
}

// endsNegated is whether rs ends with n't, or with not, never or no longer after a word boundary.
func endsNegated(rs []rune) bool {
	if _, ok := endsWith(rs, negatedSuffix); ok {
		return true
	}
	for _, w := range negations {
		if i, ok := endsWith(rs, w); ok && boundary(rs, i) {
			return true
		}
	}
	return false
}

// negated is NEGATED.search over rs, the text before a fix verb: a negation, white space, and at most
// one word and its white space before the verb ("doesn't fix", "not yet fixing").
func negated(rs []rune) bool {
	head := trimRight(rs, isSpace)
	if len(head) == len(rs) {
		return false
	}
	if endsNegated(head) {
		return true
	}
	word := trimRight(head, isWord)
	before := trimRight(word, isSpace)
	return len(word) < len(head) && len(before) < len(word) && endsNegated(before)
}

// prRef is pr_ref: where in a clause PR n of repo is named, by its URL, as repo#n, or with bare as #n.
type prRef struct {
	repo, n string
	bare    bool
}

// at is the end of the PR named at i in rs, and whether one is, trying pr_ref's alternatives in order.
func (r prRef) at(rs []rune, i int) (int, bool) {
	before := func(not string) bool { return i == 0 || !(isWord(rs[i-1]) || strings.ContainsRune(not, rs[i-1])) }
	alts := []struct {
		lit string
		ok  bool
	}{
		{"github.com/" + r.repo + "/pull/" + r.n, true},
		{r.repo + "#" + r.n, before(notBeforeRepo)},
		{"#" + r.n, r.bare && before(notBeforeBare)},
	}
	for _, a := range alts {
		if end, ok := literalAt(rs, i, a.lit); a.ok && ok && (end == len(rs) || !isDigit(rs[end])) {
			return end, true
		}
	}
	return i, false
}

// starts is finditer over rs for the PR: the start of each match, each search going on from the last end.
func (r prRef) starts(rs []rune) []int {
	var out []int
	for i := 0; i < len(rs); i++ {
		if end, ok := r.at(rs, i); ok {
			out = append(out, i)
			i = end - 1
		}
	}
	return out
}

// FixesPR is report.py's fixes_pr: whether text, the title and body of the PR whose pr_key is by, says
// it fixes the PR whose pr_key is key. That is: in a clause that is not notAFix, its URL, owner/repo#N,
// or a bare #N when both are in one repo, whose governing fix verb (the nearest fixVerbs match ending
// within fixReach characters before it) has no negation directly before it. "Fixes #1 and doesn't fix
// #4" fixes #1 and not #4. Python's \w, \s, \d, \b and re.I take Unicode, and so does FixesPR. key's N
// is matched as text, as Python matches any N with no regex metacharacter; a pr_key's N is digits.
func FixesPR(text, key, by string) bool {
	repo, n, _ := strings.Cut(key, "#")
	byRepo, _, _ := strings.Cut(by, "#")
	if n == "" {
		return false
	}
	ref := prRef{repo, n, byRepo == repo}
	for _, c := range clauses([]rune(text)) {
		if len(findAll(c, notAFix)) > 0 {
			continue
		}
		for _, at := range ref.starts(c) {
			verbs := findAll(c[:at], fixVerbs)
			if len(verbs) == 0 {
				continue
			}
			v := verbs[len(verbs)-1]
			if at-v.end <= fixReach && !negated(c[:v.start]) {
				return true
			}
		}
	}
	return false
}

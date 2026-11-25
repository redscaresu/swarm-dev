package merge

import (
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"
)

// reSpecial is every character Python's re.escape puts a backslash before (3.7 and later). glob
// escapes the same ones, so its regex is the string ci_gate.py's glob builds: regexp.QuoteMeta
// leaves - bare, which a class the pattern leaves open reads as a range.
const reSpecial = "\t\n\v\f\r #$&()*+-.?[\\]^{|}~"

// classEscapes is the letters a backslash may stand before in a class: RE2 and Python's re read
// each as the same control character. \x takes two hex digits too (classEscapeWhy).
const classEscapes = "afnrtv"

// badPattern is a filter pattern glob does not read: RE2 cannot compile its regex, or would read
// it apart from Python's re. It is apart from ci_gate.py's Unread, a workflow's YAML that is not
// read. pr_expected takes both as triggers not read. In expected and main both end the run, and
// expected puts the workflow's path before Unread's text only.
type badPattern struct {
	pattern string
	why     string
}

func (e *badPattern) Error() string {
	return fmt.Sprintf("bad filter pattern %q: %s", e.pattern, e.why)
}

// glob is a GitHub filter pattern as ci_gate.py's glob has it: * stops at /, ** does not, **/ is
// zero or more folders, ? and + repeat what precedes, and a [..] class is the regex's own.
//
// The regex is the string Python builds. Where RE2 and Python's re would read it apart, glob
// returns a badPattern instead:
//   - A repeat after a repeat (*+, **+, ?+, ++). Python 3.11 and later read it as possessive, and
//     older ones refuse it. RE2 refuses it.
//   - A [ with no ] after it. Python drops that [ without a word.
//   - [: in a class. RE2 reads it as a POSIX class, Python as the two characters.
//   - An escape in a class other than punctuation, \a \f \n \r \t \v and \xHH. \d, \s, \w and their
//     capitals are Unicode on Python and ASCII on RE2. RE2 reads \p, \x{..} and octal past \377, which Python
//     refuses. Octal at or under \377 is refused too: no filter needs it.
//
// Any other regex RE2 cannot compile is a badPattern as well.
func glob(p string) (*regexp.Regexp, error) {
	src, err := globRegex(p)
	if err != nil {
		return nil, err
	}
	if why := classWhy(src); why != "" {
		return nil, &badPattern{p, why}
	}
	re, err := regexp.Compile(`\A(?:` + src + `)\z`) // loose-match: ok the pattern is a workflow's filter, translated as ci_gate.py's glob does
	if err != nil {
		return nil, &badPattern{p, strings.TrimPrefix(err.Error(), "error parsing regexp: ")}
	}
	return re, nil
}

// globRegex is the regex ci_gate.py's glob builds from p, without its \Z, token by token as its
// re.findall has them.
func globRegex(p string) (string, error) {
	var out strings.Builder
	for i := 0; i < len(p); {
		rest := p[i:]
		n := 1
		switch {
		case strings.HasPrefix(rest, "**/"):
			out.WriteString("(?:.*/)?")
			n = 3
		case strings.HasPrefix(rest, "**"):
			out.WriteString(".*")
			n = 2
		case rest[0] == '*':
			out.WriteString("[^/]*")
		case rest[0] == '[':
			end := strings.IndexByte(rest, ']')
			if end < 0 {
				return "", &badPattern{p, "a [ with no ] after it"}
			}
			n = end + 1
			out.WriteString(rest[:n])
		case rest[0] == '?' || rest[0] == '+':
			out.WriteByte(rest[0])
		default:
			if n = strings.IndexAny(rest, "*?+["); n < 0 {
				n = len(rest)
			}
			out.WriteString(reEscape(rest[:n]))
		}
		i += n
	}
	return out.String(), nil
}

// reEscape is s as Python's re.escape writes it.
func reEscape(s string) string {
	var out strings.Builder
	for i := 0; i < len(s); i++ {
		if strings.IndexByte(reSpecial, s[i]) >= 0 {
			out.WriteByte('\\')
		}
		out.WriteByte(s[i])
	}
	return out.String()
}

// classWhy says why RE2 would read a class in the regex src apart from Python's re, or "" when it
// reads every one the same. A class runs from its [ to the first ] past the first character (past
// a leading ^ too), as both read it, so a class the pattern leaves open (a [] token, or a \] that
// ends one) is judged to where it really ends. Outside a class, src's only escapes are
// re.escape's, which both read as the character.
func classWhy(src string) string {
	for i := 0; i < len(src); i++ {
		switch src[i] {
		case '\\':
			i++
		case '[':
			j := i + 1
			if j < len(src) && src[j] == '^' {
				j++
			}
			if j < len(src) && src[j] == ']' {
				j++
			}
			for ; j < len(src) && src[j] != ']'; j++ {
				if src[j] == '[' && strings.HasPrefix(src[j+1:], ":") {
					return "RE2 reads [: in a class as a POSIX class, where Python's re reads [ and :"
				}
				if src[j] == '\\' {
					if why := classEscapeWhy(src[j+1:]); why != "" {
						return why
					}
					j++
				}
			}
			i = j
		}
	}
	return ""
}

// classEscapeWhy says why RE2 would read the escape \<rest> in a class apart from Python's re, or ""
// when both read it as the same character.
func classEscapeWhy(rest string) string {
	r, _ := utf8.DecodeRuneInString(rest)
	switch {
	case rest == "":
		return ""
	case r < utf8.RuneSelf && !isAlnum(byte(r)):
		return ""
	case strings.ContainsRune(classEscapes, r):
		return ""
	case r == 'x' && len(rest) >= 3 && isHex(rest[1]) && isHex(rest[2]):
		return ""
	}
	return fmt.Sprintf(`RE2 reads \%c in a class apart from Python's re, or not at all`, r)
}

func isAlnum(c byte) bool {
	return '0' <= c && c <= '9' || 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z'
}

func isHex(c byte) bool {
	return '0' <= c && c <= '9' || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F'
}

// match reports whether s matches the filter list pats, as ci_gate.py's match has it: the last
// pattern s matches decides, and one starting with ! negates. It reads every pattern, in order, and
// the first one glob refuses is its error.
func match(s string, pats []string) (bool, error) {
	hit := false
	for _, p := range pats {
		neg := strings.HasPrefix(p, "!")
		re, err := glob(strings.TrimPrefix(p, "!"))
		if err != nil {
			return false, err
		}
		if re.MatchString(s) {
			hit = !neg
		}
	}
	return hit, nil
}

// fileList is the paths a push or a PR changes, as ci_gate.py's pr_files gives them. known false is
// pr_files' None, a list it could not read in full; a list it read with no path is known and empty.
type fileList struct {
	paths []string
	known bool
}

// covers reports whether pushing files to base runs a workflow whose filters for the event are f,
// as ci_gate.py's covers has it. f nil is on_filters' None, no such trigger, which covers nothing;
// an empty f is {}, the trigger with no filters. A file list not known covers any path filter, so
// the wait fails closed. A pattern glob refuses is the error, once covers reads it.
func covers(f map[string][]string, base string, files fileList) (bool, error) {
	if f == nil {
		return false, nil
	}
	branches, onBranches := f["branches"]
	ignored, onIgnored := f["branches-ignore"]
	if onBranches {
		if ok, err := match(base, branches); err != nil || !ok {
			return false, err
		}
	}
	if onIgnored {
		if ok, err := match(base, ignored); err != nil || ok {
			return false, err
		}
	}
	_, onTags := f["tags"]
	_, onTagsIgnored := f["tags-ignore"]
	if !onBranches && !onIgnored && (onTags || onTagsIgnored) {
		return false, nil
	}
	if !files.known {
		return true, nil
	}
	if pats, ok := f["paths"]; ok {
		if hit, err := anyMatch(files.paths, pats); err != nil || !hit {
			return false, err
		}
	}
	if pats, ok := f["paths-ignore"]; ok {
		if all, err := allMatch(files.paths, pats); err != nil || all {
			return false, err
		}
	}
	return true, nil
}

// anyMatch reports whether any of paths matches pats, stopping at the first, as Python's any does.
func anyMatch(paths, pats []string) (bool, error) {
	for _, x := range paths {
		if hit, err := match(x, pats); err != nil || hit {
			return hit, err
		}
	}
	return false, nil
}

// allMatch reports whether every one of paths matches pats, stopping at the first that does not,
// as Python's all does: true for no paths.
func allMatch(paths, pats []string) (bool, error) {
	for _, x := range paths {
		if hit, err := match(x, pats); err != nil || !hit {
			return false, err
		}
	}
	return true, nil
}

// onBoard reports whether path p is on the board's paths, board being merge.sh's board_paths, one
// entry each, as ci_gate.py's on_board has them. An entry ending in / is a folder; one whose last
// part holds a * is a glob, whose last * is any run of characters, slashes too, with its text either
// side taken as it is, so a board folder named with a * stays literal; any other entry is a file.
// So Board.base is not Board.base.py, and retros/*.md takes retros/v1.0.0.md, not retros/x.sh.
func onBoard(p string, board []string) bool {
	for _, b := range board {
		if onEntry(p, b) {
			return true
		}
	}
	return false
}

// onEntry reports whether path p is on the one board entry b, as onBoard reads it.
func onEntry(p, b string) bool {
	if strings.HasSuffix(b, "/") {
		return strings.HasPrefix(p, b)
	}
	if !strings.Contains(b[strings.LastIndexByte(b, '/')+1:], "*") {
		return p == b
	}
	star := strings.LastIndexByte(b, '*')
	pre, suf := b[:star], b[star+1:]
	return len(p) >= len(pre)+len(suf) && strings.HasPrefix(p, pre) && strings.HasSuffix(p, suf)
}

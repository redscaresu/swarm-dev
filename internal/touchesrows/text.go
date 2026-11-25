// Package touchesrows holds the text rules of bin/lib/touches_rows.py: a story's front matter, a
// touches part's first word, when two touches entries clash, and a story's depends_on. The Python
// copy stays until its last importer is ported, and text_compare_test.go runs both over the same
// inputs. Reading a story's files is files.go's.
package touchesrows

import (
	"strings"
	"unicode"
)

// Entry is one entry of a story's touches: its repo, its file and the part of the file it names,
// with Part "" for the bare file.
type Entry struct {
	Repo, File, Part string
}

// SkipWords are a part's leading words that name no function or section: a section marker and the
// articles, compared in lower case (doc headings start with "The ...").
var SkipWords = map[string]bool{"§": true, "#": true, "the": true, "a": true, "an": true}

// Pairs adds each line's key and value to out, as board.sh's awk reads them: the key is the text
// before the line's first colon, and the value the text after it with its leading spaces dropped.
// A line with no colon adds nothing, and a key already in out keeps its value.
func Pairs(lines []string, out map[string]string) {
	for _, line := range lines {
		addPair(line, out)
	}
}

// PairsUntil is Pairs over the lines before the first line equal to stop.
func PairsUntil(lines []string, out map[string]string, stop string) {
	for _, line := range lines {
		if line == stop {
			return
		}
		addPair(line, out)
	}
}

// addPair adds one line's key and value to out, as Pairs says.
func addPair(line string, out map[string]string) {
	k, v, ok := strings.Cut(line, ":")
	if _, seen := out[k]; ok && !seen {
		out[k] = strings.TrimLeft(v, " ")
	}
}

// frontMark is the line that opens and closes a story's front matter.
const frontMark = "---"

// FrontText gives a story's own front matter from its text, already decoded: each key's first
// value, as Pairs leaves it. Each line has its trailing carriage returns dropped first, so CRLF is
// tolerated. There is front matter only when the first line is ---, and it ends at the next ---
// or at the end of the text.
func FrontText(text string) map[string]string {
	lines := strings.Split(text, "\n")
	for i, l := range lines {
		lines[i] = strings.TrimRight(l, "\r")
	}
	out := map[string]string{}
	if lines[0] == frontMark {
		PairsUntil(lines[1:], out, frontMark)
	}
	return out
}

// isSpace reports whether Python's str.split() and the re module's \s split on r: Go's
// unicode.IsSpace, and also U+001C to U+001F, which Python counts as space and Go does not.
func isSpace(r rune) bool {
	return unicode.IsSpace(r) || r >= '\x1c' && r <= '\x1f'
}

// words splits s as Python's str.split() with no arguments does.
func words(s string) []string {
	return strings.FieldsFunc(s, isSpace)
}

// isSkip reports whether w is one of SkipWords once lower-cased. strings.ToLower and Python's
// lower() agree here: no character but the ASCII letters lower-cases to one holding t, h, e, a or
// n, checked over every code point with Python 3.14 on 2026-11-24.
func isSkip(w string) bool {
	return SkipWords[strings.ToLower(w)]
}

// FirstWord gives a part's first word past SkipWords (a function or section name), as it is
// written: only the check against SkipWords lower-cases it, so Foo and foo are two words. A part
// with nothing past them gives its last word (a section named A), and a part with no words, a bare
// file's, gives "".
func FirstWord(part string) string {
	ws := words(part)
	for _, w := range ws {
		if !isSkip(w) {
			return w
		}
	}
	if len(ws) == 0 {
		return ""
	}
	return ws[len(ws)-1]
}

// Overlap reports whether two touches entries clash: the same repo and file, and either both parts
// empty or the parts' first words the same. A bare file never clashes with a part of it.
func Overlap(a, b Entry) bool {
	return a.Repo == b.Repo && a.File == b.File && FirstWord(a.Part) == FirstWord(b.Part)
}

// isDepSep reports whether depends_on splits on r: a space as isSpace says, a comma, a bracket or a
// quote.
func isDepSep(r rune) bool {
	return isSpace(r) || strings.ContainsRune(`,[]"'`, r)
}

// Deps gives the slugs fm's depends_on names: its text before the first #, split on each run of
// spaces, commas, brackets and quotes. As Python's re.split does, a run at either end leaves an
// empty slug, and so does an empty or missing depends_on.
func Deps(fm map[string]string) map[string]bool {
	text, _, _ := strings.Cut(fm["depends_on"], "#")
	out, start, inSep := map[string]bool{}, 0, false
	for i, r := range text {
		switch {
		case isDepSep(r) && !inSep:
			out[text[start:i]], inSep = true, true
		case !isDepSep(r) && inSep:
			start, inSep = i, false
		}
	}
	if inSep {
		out[""] = true
	} else {
		out[text[start:]] = true
	}
	return out
}

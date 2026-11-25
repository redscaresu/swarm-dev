package merge

// The remerge diff's removed lines, and the text the dropped-lines check prints, as the Python helper
// it replaced read them (bin/lib's dropped_lines, as tag v0.32.0 has it): its unquote, removed and
// clean, and the cut its scan made. dropped.go's check is built on them.

import (
	"bytes"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"unicode/utf8"
)

// droppedTextChars is the most characters of a dropped line's text the check prints, Python's
// TEXT_CHARS (merge.sh's FIX_MAIN_LINE_CHARS).
const droppedTextChars = 300

// droppedSection is where a line of the remerged file sits, Python's OUTSIDE, FIRST, SECOND and
// ANCESTOR, with the same values.
type droppedSection int

const (
	droppedOutside  droppedSection = iota // outside any conflict section
	droppedFirst                          // the first parent's part, after the opening <<<<<<< line
	droppedSecond                         // the second parent's part, after the ======= line
	droppedAncestor                       // the merge base's part, after a ||||||| line
)

var (
	// droppedHunk is Python's HUNK: a hunk header, with the old and the new count each a group that
	// is empty where the header leaves the count out.
	droppedHunk = regexp.MustCompile(`^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@`)
	// droppedMarker is Python's MARKER: a conflict marker line of seven or more of its character.
	droppedMarker = regexp.MustCompile(`^(?:<{7,}|\|{7,}|>{7,})(?: |$)|^={7,}$`)
	// droppedOpening is the marker that opens a section, outside one.
	droppedOpening = regexp.MustCompile(`^<{7,}(?: |$)`)
)

// droppedEscapes is Python's ESCAPES: the byte each C-style escape letter in a quoted path stands
// for. Any other byte after a backslash stands for itself.
var droppedEscapes = map[byte]byte{'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11}

// droppedLine is one line the remerge diff removes, as Python's removed yields it.
type droppedLine struct {
	file     []byte         // the remerged file's name: the --- line's, its a/ taken off
	after    []byte         // the file's name in the merge: the +++ line's, its b/ taken off
	hasAfter bool           // false where the +++ line names no b/ file (/dev/null): Python's None
	section  droppedSection // the conflict section the line sits in
	text     []byte         // the line, its leading - taken off
}

// droppedUnquote is Python's unquote: a path as git's diff header writes it, its C-style quotes and
// escapes taken off. A path that does not both start and end with a double quote comes back as it
// is. Inside the quotes, a backslash followed by three ASCII digits, or by one or two at the end, is
// the byte those digits give in octal. A backslash followed by any other byte is that byte's escape
// in droppedEscapes, or the byte itself, and a backslash at the end is kept. Digits 8 or 9, or a value
// over 255, are an error, where Python raises (git writes neither).
func droppedUnquote(path []byte) ([]byte, error) {
	if !bytes.HasPrefix(path, []byte(`"`)) || !bytes.HasSuffix(path, []byte(`"`)) {
		return path, nil
	}
	s := path[1:max(1, len(path)-1)] // a lone " is both ends, so nothing is inside
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); {
		if s[i] == '\\' && i+1 < len(s) {
			next := s[i+1]
			if digits := s[i+1 : min(i+4, len(s))]; droppedAllDigits(digits) {
				b, err := strconv.ParseUint(string(digits), 8, 8)
				if err != nil {
					return nil, fmt.Errorf("cannot unquote the diff header's path %q: \\%s is not an octal byte: %w", path, digits, err)
				}
				out = append(out, byte(b))
				i += 4
				continue
			}
			if b, ok := droppedEscapes[next]; ok {
				next = b
			}
			out = append(out, next)
			i += 2
			continue
		}
		out = append(out, s[i])
		i++
	}
	return out, nil
}

// droppedAllDigits is Python's bytes.isdigit: b is not empty and every byte of it is an ASCII digit.
func droppedAllDigits(b []byte) bool {
	if len(b) == 0 {
		return false
	}
	for _, c := range b {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// droppedRemoved is Python's removed: each line the remerge diff removes, with the remerged file's
// name, the file's name in the merge and the conflict section the line sits in, conflict markers
// left out. A hunk's counts come from its header, a missing count meaning 1. A "\ No newline at end
// of file" line counts against neither. A section is followed across the hunks of a file, and a new
// diff --git line ends it. Inside a section, every line droppedMarker matches is left out, whatever
// the size of the opening marker. Only a run of exactly the opening's size changes the section, and
// the marker test is taken before the change. A line is kept only where the --- line named an a/
// file. On a header path droppedUnquote cannot read, it returns the lines before that header with
// the error: Python's generator yields those before it raises, so a caller handles them first.
func droppedRemoved(diff []byte) ([]droppedLine, error) {
	var (
		found                  []droppedLine
		file, after            []byte
		hasFile, hasAfter      bool
		header                 bool
		oldLeft, newLeft, size int
		section                = droppedOutside
	)
	for _, line := range bytes.Split(diff, []byte("\n")) {
		if oldLeft > 0 || newLeft > 0 {
			tag, text := line[:min(1, len(line))], line[min(1, len(line)):]
			if string(tag) == `\` {
				continue
			}
			if string(tag) == "+" {
				newLeft--
				continue
			}
			oldLeft--
			if string(tag) != "-" {
				newLeft--
			}
			marker := section != droppedOutside && droppedMarker.Match(text)
			switch {
			case section == droppedOutside && droppedOpening.Match(text):
				section, size, marker = droppedFirst, len(text)-len(bytes.TrimLeft(text, "<")), true
			case (section == droppedFirst || section == droppedAncestor) && bytes.Equal(text, bytes.Repeat([]byte("="), size)):
				section = droppedSecond
			case section == droppedFirst && droppedRunOf(text, '|', size):
				section = droppedAncestor
			case section == droppedSecond && droppedRunOf(text, '>', size):
				section = droppedOutside
			}
			if string(tag) == "-" && !marker && hasFile {
				found = append(found, droppedLine{file: file, after: after, hasAfter: hasAfter, section: section, text: text})
			}
			continue
		}
		switch {
		case bytes.HasPrefix(line, []byte("diff --git ")):
			file, after, hasFile, hasAfter, header, section = nil, nil, false, false, true, droppedOutside
		case header && (bytes.HasPrefix(line, []byte("--- ")) || bytes.HasPrefix(line, []byte("+++ "))):
			name, err := droppedUnquote(bytes.TrimRight(line[4:], "\t"))
			if err != nil {
				return found, err
			}
			if bytes.HasPrefix(line, []byte("--- ")) {
				file, hasFile = droppedName(name, "a/")
			} else {
				after, hasAfter = droppedName(name, "b/")
			}
		case header || hasFile:
			if m := droppedHunk.FindSubmatchIndex(line); m != nil {
				header = false
				oldLeft, newLeft = droppedHunkCount(line, m[2], m[3]), droppedHunkCount(line, m[4], m[5])
			}
		}
	}
	return found, nil
}

// droppedName is Python's name[2:] if name.startswith(prefix) else None: the name with prefix taken
// off and true, or nil and false where it does not start with prefix (/dev/null).
func droppedName(name []byte, prefix string) ([]byte, bool) {
	rest, ok := bytes.CutPrefix(name, []byte(prefix))
	if !ok {
		return nil, false
	}
	return rest, true
}

// droppedRunOf is Python's text[:size + 1] in (c * size, c * size + b" "): text is size of c and
// nothing else, or size of c and then a space.
func droppedRunOf(text []byte, c byte, size int) bool {
	run := bytes.Repeat([]byte{c}, size)
	head := text[:min(size+1, len(text))]
	return bytes.Equal(head, run) || bytes.Equal(head, append(run, ' '))
}

// droppedHunkCount is a hunk count: the digits line[start:end] holds, or 1 where droppedHunk's group did
// not take part (start < 0). Python's int has no limit, so a count past the largest int is taken as
// that, which no diff that fits in memory can tell apart.
func droppedHunkCount(line []byte, start, end int) int {
	if start < 0 {
		return 1
	}
	n, err := strconv.Atoi(string(line[start:end]))
	if err != nil { // the group is ASCII digits, so the only error is a count out of range
		return math.MaxInt
	}
	return n
}

// droppedClean is Python's clean: b decoded as bytes.decode("utf-8", "replace") does, then the
// characters U+0000 to U+001F and U+007F taken off. The decode puts one U+FFFD in place of each
// maximal invalid subpart (droppedSubpart), not one per invalid byte and not one per run of them.
func droppedClean(b []byte) string {
	out := make([]byte, 0, len(b))
	for i := 0; i < len(b); {
		if c := b[i]; c < utf8.RuneSelf {
			if c >= 0x20 && c != 0x7f {
				out = append(out, c)
			}
			i++
			continue
		}
		n, whole := droppedSubpart(b[i:])
		if whole {
			out = append(out, b[i:i+n]...)
		} else {
			out = utf8.AppendRune(out, utf8.RuneError)
		}
		i += n
	}
	return string(out)
}

// droppedSubpart reads the sequence that starts at b[0], a byte of 0x80 or more: its length and
// true where it is a whole UTF-8 character, else the length of its maximal invalid subpart and
// false. That subpart is the lead byte and each continuation byte after it that its ranges allow,
// up to the first that does not fit; a byte that cannot lead is a subpart of one.
func droppedSubpart(b []byte) (int, bool) {
	size, lo, hi := droppedLead(b[0])
	if size == 0 {
		return 1, false
	}
	n := 1
	for n < size && n < len(b) && b[n] >= lo && b[n] <= hi {
		n++
		lo, hi = 0x80, 0xbf // only the first continuation byte has a narrower range
	}
	return n, n == size
}

// droppedLead gives, for a lead byte, the length of the character it starts and the range its first
// continuation byte must be in, as Unicode's table of well-formed UTF-8 sets them. A byte that never
// leads (0x80 to 0xc1, and 0xf5 to 0xff) gives a length of 0.
func droppedLead(c byte) (int, byte, byte) {
	switch {
	case c >= 0xc2 && c <= 0xdf:
		return 2, 0x80, 0xbf
	case c == 0xe0:
		return 3, 0xa0, 0xbf // below 0xa0 would be an overlong form
	case c == 0xed:
		return 3, 0x80, 0x9f // above 0x9f would be a surrogate
	case c >= 0xe1 && c <= 0xef:
		return 3, 0x80, 0xbf
	case c == 0xf0:
		return 4, 0x90, 0xbf // below 0x90 would be an overlong form
	case c >= 0xf1 && c <= 0xf3:
		return 4, 0x80, 0xbf
	case c == 0xf4:
		return 4, 0x80, 0x8f // above 0x8f would be past U+10FFFF
	}
	return 0, 0, 0
}

// droppedCut is the text droppedClean gives cut to droppedTextChars characters, as Python's
// clean(text)[:TEXT_CHARS] cuts it: it counts characters, not bytes.
func droppedCut(text string) string {
	n := 0
	for i := range text {
		if n == droppedTextChars {
			return text[:i]
		}
		n++
	}
	return text
}

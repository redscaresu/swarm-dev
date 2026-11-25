package merge

// The workflow trigger reader: ci_gate.py's Unread, unq, flow and on_filters (bin/lib/ci_gate.py:19-20,
// :445-505). It reads a workflow's on: key from its text without a YAML parser, and YAML it does not
// read is Unread, never a guess. Nothing runs it yet: until the switch, ci_gate.py's copy decides.

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"
)

// Unread is a workflow written in YAML the trigger reader does not read: never retried, never
// skipped. Its text is ci_gate.py's message, word for word.
type Unread struct{ msg string }

func (e *Unread) Error() string { return e.msg }

// unread is an Unread error with its text formatted as Python's % formats it.
func unread(format string, args ...any) error {
	return &Unread{msg: fmt.Sprintf(format, args...)}
}

// onKeys are the spellings of the top-level key on_filters reads as on: YAML 1.1 reads a bare on as
// true.
var onKeys = []string{"on", `"on"`, "'on'", "true"}

// noFilters are the values an event's key may have when it has no filters, or filters on the lines
// below it.
var noFilters = []string{"", "{}", "null", "~"}

// quotedEntry is a quoted entry in a [flow] list, as flow finds them.
var quotedEntry = regexp.MustCompile(`'[^']*'|"[^"]*"`)

// pySpace reports whether r is whitespace as Python's str.isspace and its re's \s have it, which
// counts U+001C to U+001F where Go's unicode.IsSpace does not.
func pySpace(r rune) bool {
	switch r {
	case '\t', '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x1f, ' ',
		0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000:
		return true
	}
	return r >= 0x2000 && r <= 0x200a
}

// pyBreak reports whether r ends a line as Python's str.splitlines has it.
func pyBreak(r rune) bool {
	switch r {
	case '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
		return true
	}
	return false
}

// pyLines splits text as Python's str.splitlines does: at each pyBreak, \r\n as one, with no line
// after a final break.
func pyLines(text string) []string {
	var lines []string
	for text != "" {
		i := strings.IndexFunc(text, pyBreak)
		if i < 0 {
			return append(lines, text)
		}
		lines = append(lines, text[:i])
		r, size := utf8.DecodeRuneInString(text[i:])
		text = text[i+size:]
		if r == '\r' {
			text = strings.TrimPrefix(text, "\n")
		}
	}
	return lines
}

// pyStrip is Python's s.strip(): pySpace off both ends.
func pyStrip(s string) string { return strings.TrimFunc(s, pySpace) }

// uncomment drops a line's comment as re.sub(r"(^|\s)#.*", "", line) does: from the first # that
// starts the line or follows whitespace, with that whitespace, to the end.
func uncomment(line string) string {
	prev, prevAt := rune(0), 0
	for i, r := range line {
		if r == '#' && (i == 0 || pySpace(prev)) {
			return line[:prevAt]
		}
		prev, prevAt = r, i
	}
	return line
}

// isOnKey reports whether line starts with an on: key, as re.match(r"""^(on|"on"|'on'|true)\s*:""",
// line) does.
func isOnKey(line string) bool {
	for _, k := range onKeys {
		rest, ok := strings.CutPrefix(line, k)
		if ok && strings.HasPrefix(strings.TrimLeftFunc(rest, pySpace), ":") {
			return true
		}
	}
	return false
}

// indent is how many characters (not bytes) of whitespace start line, as Python's
// len(l) - len(l.lstrip()) counts them.
func indent(line string) int {
	return utf8.RuneCountInString(line[:len(line)-len(strings.TrimLeftFunc(line, pySpace))])
}

// unq is a scalar, unquoted. An anchor (&a) or alias (*a) is not read: as a literal glob it would
// match nothing and skip the workflow.
func unq(s string) (string, error) {
	s = pyStrip(s)
	if strings.HasPrefix(s, "&") || strings.HasPrefix(s, "*") {
		return "", unread("%s: YAML anchors and aliases are not read", s)
	}
	return strings.Trim(s, `'"`), nil
}

// flow is a value as a list: a [flow] list's entries, or one scalar, unquoted, without empty ones.
func flow(v string) ([]string, error) {
	v = pyStrip(v)
	if strings.HasPrefix(v, "{") || strings.HasPrefix(v, "[") != strings.HasSuffix(v, "]") {
		return nil, unread("%s: a {flow mapping} or a [list] over several lines is not read", v)
	}
	for _, q := range quotedEntry.FindAllString(v, -1) {
		if strings.Contains(q, ",") {
			return nil, unread("%s: a quoted entry holding a comma is not read", v)
		}
	}
	list := []string{}
	for _, x := range strings.Split(strings.Trim(v, "[]"), ",") {
		s, err := unq(x)
		if err != nil {
			return nil, err
		}
		if s != "" {
			list = append(list, s)
		}
	}
	return list, nil
}

// onFilters is on: <event>'s filters, empty for none, with on false when the workflow has no such
// trigger (ci_gate.py's None). It reads the forms workflows use: on: push, on: [push, ...], and a
// block of events with block or [flow] lists. text is the workflow as ci_gate.py's gh returns it.
func onFilters(text, event string) (filters map[string][]string, on bool, err error) {
	lines := pyLines(text)
	for i, l := range lines {
		lines[i] = strings.TrimRightFunc(uncomment(l), pySpace)
	}
	top := slices.IndexFunc(lines, isOnKey)
	if top < 0 {
		return nil, false, unread("no on: key")
	}
	_, v, _ := strings.Cut(lines[top], ":")
	if pyStrip(v) == "" {
		return blockFilters(eventBlock(lines[top+1:]), event)
	}
	events, err := flow(v)
	if err != nil || !slices.Contains(events, event) {
		return nil, false, err
	}
	return map[string][]string{}, true, nil
}

// eventBlock is the lines that are not blank after on:, up to the next top-level key. A line that
// starts with - at the margin stays in.
func eventBlock(lines []string) []string {
	var block []string
	for _, l := range lines {
		first, _ := utf8.DecodeRuneInString(l)
		if l != "" && !pySpace(first) && first != '-' {
			break
		}
		if pyStrip(l) != "" {
			block = append(block, l)
		}
	}
	return block
}

// blockFilters is event's filters in a block of events: a - <event> item has none; an <event>: key
// has the lines indented below it. Only the lines at the first line's indent name events.
func blockFilters(block []string, event string) (map[string][]string, bool, error) {
	for j, l := range block {
		if indent(l) != indent(block[0]) {
			continue
		}
		k := pyStrip(l)
		if item, isItem := strings.CutPrefix(k, "-"); isItem {
			name, err := unq(item)
			if err != nil {
				return nil, false, err
			}
			if name == event {
				return map[string][]string{}, true, nil
			}
			continue
		}
		key, rest, _ := strings.Cut(k, ":")
		name, err := unq(key)
		if err != nil {
			return nil, false, err
		}
		if name != event {
			continue
		}
		if r := pyStrip(rest); !slices.Contains(noFilters, r) {
			return nil, false, unread("%s: %s is not read", event, r)
		}
		f, err := eventFilters(block[j+1:], indent(l), event)
		return f, err == nil, err
	}
	return nil, false, nil
}

// eventFilters reads the filters on the lines indented past at, up to the first that is not: a
// <key>: line starts a filter with its [flow] or scalar value, and a - item adds to the last one.
func eventFilters(lines []string, at int, event string) (map[string][]string, error) {
	// key is the last filter's name. Empty is Python's None and its "" alike: both are false, so a
	// - item after either is not read as an entry.
	f, key := map[string][]string{}, ""
	for _, l := range lines {
		if indent(l) <= at {
			break
		}
		c := pyStrip(l)
		item, isItem := strings.CutPrefix(c, "-")
		switch {
		case isItem && key != "":
			v, err := unq(item)
			if err != nil {
				return nil, err
			}
			f[key] = append(f[key], v)
		case strings.Contains(c, ":"):
			name, rest, _ := strings.Cut(c, ":")
			k, err := unq(name)
			if err != nil {
				return nil, err
			}
			list, err := flow(rest)
			if err != nil {
				return nil, err
			}
			key, f[k] = k, list
		default:
			return nil, unread("%s: %s is not read", event, c)
		}
	}
	return f, nil
}

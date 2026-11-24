package merge

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"unicode"
)

// workflow is a workflow's text, one line per argument.
func workflow(lines ...string) string { return strings.Join(lines, "\n") + "\n" }

// result is what ci_gate.py's on_filters gave, as the Python run printed it: None for no such
// trigger, the filters as json.dumps(f, sort_keys=True, separators=(",", ":")) prints them, or
// "Unread: " and the message.
func result(filters map[string][]string, on bool, err error) string {
	var u *Unread
	switch {
	case errors.As(err, &u):
		return "Unread: " + u.Error()
	case err != nil:
		return "not Unread: " + err.Error()
	case !on:
		return "None"
	}
	b, err := json.Marshal(filters)
	if err != nil {
		return "unprintable: " + err.Error()
	}
	return string(b)
}

// The rows of TestOnFilters. Each want is what ci_gate.py's on_filters gave on the same text and event,
// run by python3 3.14.7 on 2026-11-24; the PR that added this table has the run. A file: text is a
// workflow under testdata/workflows, a copy of this repo's own.
var filterRows = []struct {
	name, text, event, want string
}{
	// on: <event> and on: [<event>, ...].
	{"on: push", "on: push\n", "push", "{}"},
	{"on: push, another event", "on: push\n", "pull_request", "None"},
	{"on: [list]", "on: [push, pull_request]\n", "pull_request", "{}"},
	{"on: [list], another event", "on: [push, pull_request]\n", "workflow_dispatch", "None"},

	// A block of events.
	{"block lists", workflow("on:", "  push:", "    branches:", "      - main", "      - 'release/**'",
		"    paths-ignore:", `      - "docs/**"`), "push", `{"branches":["main","release/**"],"paths-ignore":["docs/**"]}`},
	{"[flow] lists and a scalar", workflow("on:", "  pull_request:", `    branches: [main, "dev"]`,
		"    types: [opened, synchronize]", "    paths: 'bin/**'"), "pull_request",
		`{"branches":["main","dev"],"paths":["bin/**"],"types":["opened","synchronize"]}`},
	{"{} value", workflow("on:", "  push: {}", "  pull_request:"), "push", "{}"},
	{"null value", workflow("on:", "  push: null", "  pull_request:"), "push", "{}"},
	{"~ value", workflow("on:", "  push: ~", "  pull_request:"), "push", "{}"},
	{"empty value, last line", workflow("on:", "  push:", "  merge_group:"), "merge_group", "{}"},
	{"empty filter", workflow("on:", "  push:", "    paths:"), "push", `{"paths":[]}`},
	{"comments", workflow("on: # the triggers", "  # a line at any indent", "  push: # none here",
		"    branches: [main] # the default", "    paths:", "# a line at the margin", "      - a#b",
		"      - 'c' # trailing"), "push", `{"branches":["main"],"paths":["a#b","c"]}`},
	{`key "on"`, workflow(`"on":`, "  push:"), "push", "{}"},
	{"key 'on'", "'on': push\n", "push", "{}"},
	{"key true", "true: [push]\n", "push", "{}"},
	{"key with a space before :", "on : push\n", "push", "{}"},
	{"absent event", workflow("on:", "  push:", "    branches: [main]"), "pull_request", "None"},
	{"types", workflow("on:", "  pull_request:", "    types: [opened]", "  push:", "    branches: [main]"),
		"pull_request", `{"types":["opened"]}`},
	{"- event list", workflow("on:", "  - push", "  - pull_request"), "pull_request", "{}"},
	{"- event list at the margin", workflow("on:", "- push", "- pull_request", "jobs:"), "pull_request", "{}"},
	{"a nested name is not an event", workflow("on:", "  pull_request:", "    branches:", "      - push"),
		"push", "None"},
	{"a key after the block is not an event", workflow("on:", "  push:", "jobs:", "  pull_request:"),
		"pull_request", "None"},
	{"indent counted in characters", workflow("on:", "\u00a0 push:", "  pull_request:"), "pull_request", "{}"},

	// This repo's own workflows.
	{"ci.yml push", "file:ci.yml", "push", `{"branches":["main"]}`},
	{"ci.yml pull_request", "file:ci.yml", "pull_request",
		`{"types":["opened","synchronize","reopened","ready_for_review"]}`},
	{"ci.yml merge_group", "file:ci.yml", "merge_group", "{}"},
	{"release.yml push", "file:release.yml", "push", `{"branches":["main"]}`},
	{"release.yml pull_request", "file:release.yml", "pull_request", "None"},

	// Unread, one row per raise site of ci_gate.py.
	{"anchor (:450)", workflow("on:", "  push:", "    branches:", "      - &main main"), "push",
		"Unread: &main main: YAML anchors and aliases are not read"},
	{"alias (:450)", "on: [push, *events]\n", "push", "Unread: *events: YAML anchors and aliases are not read"},
	{"{flow} mapping (:456)", "on: {push: {}}\n", "push",
		"Unread: {push: {}}: a {flow mapping} or a [list] over several lines is not read"},
	{"[list] over lines (:456)", workflow("on:", "  push:", "    branches: [main,", "      dev]"), "push",
		"Unread: [main,: a {flow mapping} or a [list] over several lines is not read"},
	{"quoted comma (:458)", workflow("on:", "  push:", "    branches: ['a,b', main]"), "push",
		"Unread: ['a,b', main]: a quoted entry holding a comma is not read"},
	{"no on: key (:467)", workflow("name: x", "jobs:", "  on: push"), "push", "Unread: no on: key"},
	{"event value (:490)", workflow("on:", "  push: [main]"), "push", "Unread: push: [main] is not read"},
	{"block line (:503)", workflow("on:", "  push:", "    branches"), "push", "Unread: push: branches is not read"},
	{"- item before a key (:503)", workflow("on:", "  push:", "    - main"), "push",
		"Unread: push: - main is not read"},
}

// rowText is a row's workflow text, read from testdata for a file: row.
func rowText(t *testing.T, text string) string {
	t.Helper()
	name, isFile := strings.CutPrefix(text, "file:")
	if !isFile {
		return text
	}
	b, err := os.ReadFile(filepath.Join("testdata", "workflows", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestOnFilters(t *testing.T) {
	for _, r := range filterRows {
		t.Run(r.name, func(t *testing.T) {
			if got := result(onFilters(rowText(t, r.text), r.event)); got != r.want {
				t.Errorf("onFilters(%q, %q) = %s, want %s", r.text, r.event, got, r.want)
			}
		})
	}
}

// pythonSpace is every code point for which python3's str.isspace is true, and re's \s matches, and
// pythonBreaks every one its str.splitlines splits at: python3 3.14.7 and 3.9.6 over every code point,
// 2026-11-24 (the PR has the run).
var (
	pythonSpace = []rune{0x9, 0xa, 0xb, 0xc, 0xd, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x85, 0xa0, 0x1680,
		0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
		0x2028, 0x2029, 0x202f, 0x205f, 0x3000}
	pythonBreaks = []rune{0xa, 0xb, 0xc, 0xd, 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029}
)

// TestPythonSets checks pySpace and pyBreak hold exactly Python's code points.
func TestPythonSets(t *testing.T) {
	var space, breaks []rune
	for r := rune(0); r <= unicode.MaxRune; r++ {
		if pySpace(r) {
			space = append(space, r)
		}
		if pyBreak(r) {
			breaks = append(breaks, r)
		}
	}
	if !slices.Equal(space, pythonSpace) {
		t.Errorf("pySpace holds %U, want Python's %U", space, pythonSpace)
	}
	if !slices.Equal(breaks, pythonBreaks) {
		t.Errorf("pyBreak holds %U, want Python's %U", breaks, pythonBreaks)
	}
}

// TestPyLines checks pyLines against python3's str.splitlines on the same text (the PR has the run).
func TestPyLines(t *testing.T) {
	for _, r := range []struct {
		text string
		want []string
	}{
		{"", nil},
		{"\n", []string{""}},
		{"a\n\nb", []string{"a", "", "b"}},
		{"a\r\nb\r\n", []string{"a", "b"}},
		{"a\rb\n\rc", []string{"a", "b", "", "c"}},
		{"a\x1cb\u2028c", []string{"a", "b", "c"}},
		{"a\x1fb", []string{"a\x1fb"}},
	} {
		if got := pyLines(r.text); !slices.Equal(got, r.want) {
			t.Errorf("pyLines(%q) = %q, want %q", r.text, got, r.want)
		}
	}
}

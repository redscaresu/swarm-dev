package layers

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// judgedNames is, for each standard package whose names the rule judges, every name a package
// outside the four adapters may use: names that reach no file, no process and no standard stream. A
// name not listed fails, so a name Go adds later fails until someone lists it. Each name is written
// out in full, never matched by prefix.
var judgedNames = map[string][]string{
	"os": {
		"Getenv", "LookupEnv", "Environ", "Expand", "ExpandEnv",
		"ErrInvalid", "ErrPermission", "ErrExist", "ErrNotExist", "ErrClosed", "ErrNoDeadline",
		"ErrDeadlineExceeded", "ErrNoHandle", "ErrProcessDone",
		"IsExist", "IsNotExist", "IsPermission", "FileMode", "FileInfo",
		"ModeDir", "ModeAppend", "ModeExclusive", "ModeTemporary", "ModeSymlink", "ModeDevice",
		"ModeNamedPipe", "ModeSocket", "ModeSetuid", "ModeSetgid", "ModeCharDevice", "ModeSticky",
		"ModeIrregular", "ModeType", "ModePerm",
		"PathSeparator", "PathListSeparator",
	},
	"path/filepath": {
		"Base", "Clean", "Dir", "Ext", "FromSlash", "IsAbs", "IsLocal", "Join", "Match", "Rel", "Split",
		"SplitList", "ToSlash", "VolumeName",
		"Separator", "ListSeparator",
		"ErrBadPattern", "SkipDir", "SkipAll",
	},
	"fmt": {
		"Append", "Appendf", "Appendln", "Errorf",
		"Fprint", "Fprintf", "Fprintln", "Fscan", "Fscanf", "Fscanln", "FormatString",
		"Sprint", "Sprintf", "Sprintln", "Sscan", "Sscanf", "Sscanln",
		"Formatter", "GoStringer", "ScanState", "Scanner", "State", "Stringer",
	},
}

// wiringNames is what wiring may use beyond judgedNames: the process's arguments, its exit and the
// standard streams.
var wiringNames = map[string][]string{
	"os":  {"Args", "Exit", "Stdin", "Stdout", "Stderr"},
	"fmt": {"Print", "Printf", "Println", "Scan", "Scanf", "Scanln"},
}

// judgedPaths is the import paths judgedNames covers, sorted, so the log and the checks run in one
// order.
func judgedPaths() []string {
	paths := make([]string, 0, len(judgedNames))
	for p := range judgedNames {
		paths = append(paths, p)
	}
	slices.Sort(paths)
	return paths
}

// allowedNames is the names of the standard package imp that a package of kind may use. It is nil
// for a package the rule does not judge, and for an adapter, which the rule does not judge either.
func allowedNames(kind, imp string) []string {
	if kind == kindAdapter {
		return nil
	}
	names := slices.Clone(judgedNames[imp])
	if kind == kindWiring {
		names = append(names, wiringNames[imp]...)
	}
	return names
}

// nameFinding is one selector the rule fails.
type nameFinding struct {
	file   string // the file's slash path relative to the root
	line   int
	pkg    string // the package the file is in
	imp    string // the import path the selector's X names
	name   string
	called bool
	class  layer
}

func (f nameFinding) String() string {
	verb := "names"
	if f.called {
		verb = "calls"
	}
	return fmt.Sprintf("%s:%d: %s %s %s.%s: not on %s's names for %s", f.file, f.line, f.pkg, verb, f.imp, f.name, f.imp, f.class)
}

// nameFindings applies the names rule to the walk's records. In every package but the four adapters,
// a selector on a package judgedNames covers, under whatever name the file imports it, must be on
// allowedNames for the package's kind, whether it is called or only passed or read.
func nameFindings(records []fileRecord) []nameFinding {
	var found []nameFinding
	for _, r := range records {
		if r.class.kind == kindAdapter {
			continue
		}
		for _, s := range r.selectors {
			if _, judged := judgedNames[s.path]; !judged || slices.Contains(allowedNames(r.class.kind, s.path), s.name) {
				continue
			}
			found = append(found, nameFinding{
				file: r.path, line: s.line, pkg: r.pkg, imp: s.path, name: s.name, called: s.called, class: r.class,
			})
		}
	}
	return found
}

// nameLines is each finding as its String, in the walk's order.
func nameLines(found []nameFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// judgedSelectors is every selector the rule judges in records, as "file:line imp.name", in the
// walk's order.
func judgedSelectors(records []fileRecord) []string {
	var got []string
	for _, r := range records {
		if r.class.kind == kindAdapter {
			continue
		}
		for _, s := range r.selectors {
			if _, judged := judgedNames[s.path]; judged {
				got = append(got, fmt.Sprintf("%s:%d %s.%s", r.path, s.line, s.path, s.name))
			}
		}
	}
	return got
}

// TestNamesFixtures asserts the exact findings on the fixture trees under testdata/names/, written
// out here. bad/ has a finding for each name the rule fails and none for the names it allows beside
// them; clean/ has none, and the walk judged each of its selectors.
func TestNamesFixtures(t *testing.T) {
	m := fixtureModule
	rules := m + "/internal/rules"
	forRules := ": not on os's names for rules"
	want := []string{
		"cmd/app/main.go:11: " + m + "/cmd/app calls os.ReadFile: not on os's names for wiring",
		"internal/clock/clock.go:7: " + m + "/internal/clock names os.Stdout: not on os's names for clock",
		"internal/iface/iface.go:8: " + m + "/internal/iface calls fmt.Print: not on fmt's names for interfaces",
		"internal/rules/alias.go:7: " + rules + " calls os.ReadFile" + forRules,
		"internal/rules/files.go:8: " + rules + " calls os.ReadFile" + forRules,
		"internal/rules/files.go:12: " + rules + " names os.ReadFile" + forRules,
		"internal/rules/files.go:16: " + rules + " calls os.Remove" + forRules,
		"internal/rules/files.go:17: " + rules + " calls os.Getwd" + forRules,
		"internal/rules/files.go:18: " + rules + " calls os.Setenv" + forRules,
		"internal/rules/files.go:19: " + rules + " calls os.Exit" + forRules,
		"internal/rules/paths.go:10: " + rules + " calls path/filepath.Abs: not on path/filepath's names for rules",
		"internal/rules/paths.go:11: " + rules + " calls path/filepath.Glob: not on path/filepath's names for rules",
		"internal/rules/paths.go:12: " + rules + " calls path/filepath.WalkDir: not on path/filepath's names for rules",
		"internal/rules/print.go:7: " + rules + " calls fmt.Println: not on fmt's names for rules",
	}
	if got := nameLines(nameFindings(walkFixture(t, "names/bad"))); !slices.Equal(got, want) {
		t.Errorf("findings on names/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}
	clean := walkFixture(t, "names/clean")
	wantJudged := []string{
		"cmd/app/main.go:12 fmt.Println", "cmd/app/main.go:12 os.Args",
		"cmd/app/main.go:13 fmt.Fprintln", "cmd/app/main.go:13 os.Stderr",
		"cmd/app/main.go:14 os.Exit",
		"internal/rules/rules.go:12 os.Getenv", "internal/rules/rules.go:14 os.ErrNotExist",
		"internal/rules/rules.go:16 fmt.Sprintf", "internal/rules/rules.go:16 path/filepath.Join",
	}
	if got := judgedSelectors(clean); !slices.Equal(got, wantJudged) {
		t.Errorf("selectors judged on names/clean:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(wantJudged, "\n     "))
	}
	if got := nameFindings(clean); len(got) != 0 {
		t.Errorf("findings on names/clean, want none:\n%s", strings.Join(nameLines(got), "\n"))
	}
}

// TestRealTreeNames applies the names rule to the module itself, and logs the names each package
// may use.
func TestRealTreeNames(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	logged := map[string]bool{}
	for _, r := range records {
		if logged[r.pkg] {
			continue
		}
		logged[r.pkg] = true
		if r.class.kind == kindAdapter {
			t.Logf("names %s (%s) may use: every name, as the names rule does not judge an adapter", r.pkg, r.class)
			continue
		}
		var lists []string
		for _, p := range judgedPaths() {
			lists = append(lists, p+": "+strings.Join(allowedNames(r.class.kind, p), " "))
		}
		t.Logf("names %s (%s) may use: %s", r.pkg, r.class, strings.Join(lists, "; "))
	}
	if !logged[module+"/cmd/swarm"] {
		t.Errorf("the walk of %s found no file of cmd/swarm", root)
	}
	for _, f := range nameFindings(records) {
		t.Error(f)
	}
}

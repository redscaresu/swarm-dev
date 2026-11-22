package layers

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// allowedStd is every standard package a package outside the four adapters may import. A package
// not named here fails, so a standard package Go adds later fails until someone lists it. os,
// path/filepath and fmt pass here; their names are judged by name (go-layer-names), and time's by
// the time check (go-time-check).
var allowedStd = []string{
	"bufio", "bytes", "cmp", "context", "crypto/sha256", "encoding/base64", "encoding/csv",
	"encoding/hex", "encoding/json", "errors", "fmt", "hash", "io", "io/fs", "iter", "maps", "math",
	"math/bits", "os", "path", "path/filepath", "regexp", "slices", "sort", "strconv", "strings",
	"sync", "sync/atomic", "text/tabwriter", "time", "unicode", "unicode/utf8",
}

// bridgeFile may import bridgeImport, though no other file outside the four adapters may. It is
// cmd/swarm's bridge, which runs a form of a ported command that is still bash through bin/swarm.sh.
// It is wiring, named by its slash path relative to the root, and it goes when the last bash form does.
const (
	bridgeFile   = "cmd/swarm/bridge.go"
	bridgeImport = "os/exec"
)

// importFinding is one import the rule fails.
type importFinding struct {
	file string // the file's slash path relative to the root
	line int
	pkg  string // the importing package
	imp  string // the import path
	why  string
}

func (f importFinding) String() string {
	return fmt.Sprintf("%s:%d: %s imports %s: %s", f.file, f.line, f.pkg, f.imp, f.why)
}

// isStandard reports whether imp is a standard package's path: as the go tool decides, one whose
// first element has no dot. A path in the module is never standard.
func isStandard(imp, module string) bool {
	if inModule(imp, module) {
		return false
	}
	first, _, _ := strings.Cut(imp, "/")
	return !strings.Contains(first, ".")
}

// inModule reports whether imp is module or a package below it.
func inModule(imp, module string) bool {
	return imp == module || strings.HasPrefix(imp, module+"/")
}

// importFindings applies the import rule to the walk's records of the module named module. In every
// package but the four adapters a dot import fails; a standard import must be on allowedStd (import
// "C" is not), except bridgeImport in bridgeFile; an import of internal/adapter/... fails except in
// wiring; and a path neither standard nor in the module fails.
func importFindings(records []fileRecord, module string) []importFinding {
	var found []importFinding
	for _, r := range records {
		if r.class.kind == kindAdapter {
			continue
		}
		for _, imp := range r.imports {
			fail := func(why string) {
				found = append(found, importFinding{file: r.path, line: imp.line, pkg: r.pkg, imp: imp.path, why: why})
			}
			if imp.kind == importDot {
				fail("a dot import")
			}
			switch {
			case inModule(imp.path, module):
				if under(relTo(module, imp.path), adapterDir) && r.class.kind != kindWiring {
					fail("an adapter, which only wiring may import")
				}
			case isStandard(imp.path, module):
				if !slices.Contains(allowedStd, imp.path) && (r.path != bridgeFile || imp.path != bridgeImport) {
					fail("a standard package not on the allowed list")
				}
			default:
				fail("neither standard nor in the module")
			}
		}
	}
	return found
}

// findingLines is each finding as its String, in the walk's order.
func findingLines(found []importFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// TestImportsFixtures asserts the exact findings on the fixture trees under testdata/imports/,
// written out here: bad/ has one finding per import it holds, and clean/ has none.
func TestImportsFixtures(t *testing.T) {
	const rules = fixtureModule + "/internal/rules"
	const notAllowed = "a standard package not on the allowed list"
	want := []string{
		"cmd/app/main.go:4: " + fixtureModule + "/cmd/app imports os/exec: " + notAllowed,
		"cmd/swarm/bridge.go:6: " + fixtureModule + "/cmd/swarm imports syscall: " + notAllowed,
		"cmd/swarm/other.go:4: " + fixtureModule + "/cmd/swarm imports os/exec: " + notAllowed,
		"internal/rules/cgo.go:3: " + rules + " imports C: " + notAllowed,
		"internal/rules/dot.go:3: " + rules + " imports strings: a dot import",
		"internal/rules/exec.go:5: " + rules + " imports net: " + notAllowed,
		"internal/rules/exec.go:6: " + rules + " imports os/exec: " + notAllowed,
		"internal/rules/exec.go:7: " + rules + " imports syscall: " + notAllowed,
		"internal/rules/other.go:6: " + rules + " imports " + fixtureModule + "/internal/adapter/gh: an adapter, which only wiring may import",
		"internal/rules/other.go:7: " + rules + " imports github.com/other/lib: neither standard nor in the module",
		"internal/rules/tagged.go:6: " + rules + " imports net/http: " + notAllowed,
		"internal/rules/tools.go:4: " + rules + " imports go/parser: " + notAllowed,
		"internal/rules/tools.go:5: " + rules + " imports log: " + notAllowed,
		"internal/rules/tools.go:6: " + rules + " imports text/template: " + notAllowed,
		"internal/rules/tools.go:7: " + rules + " imports unsafe: " + notAllowed,
	}
	if got := findingLines(importFindings(walkFixture(t, "imports/bad"), fixtureModule)); !slices.Equal(got, want) {
		t.Errorf("findings on imports/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}
	clean := walkFixture(t, "imports/clean")
	if len(clean) != 5 {
		t.Errorf("the walk of imports/clean found %d files, want 5: the adapter, the wiring and its bridge, the interfaces and the rules package", len(clean))
	}
	if got := importFindings(clean, fixtureModule); len(got) != 0 {
		t.Errorf("findings on imports/clean, want none:\n%s", strings.Join(findingLines(got), "\n"))
	}
}

// TestImportsEscapedPath: an import path with an escape in it is judged as the path it spells. The
// tree is made here, as gofmt rewrites the escape and the fixtures stay gofmt-clean.
func TestImportsEscapedPath(t *testing.T) {
	root := t.TempDir()
	src := "package rules\n\nimport _ \"" + fixtureModule + "/internal/\\x61dapter/gh\"\n"
	if err := os.MkdirAll(filepath.Join(root, "internal", "rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "internal", "rules", "rules.go"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	records, err := walk(root, fixtureModule)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"internal/rules/rules.go:3: " + fixtureModule + "/internal/rules imports " + fixtureModule +
		"/internal/adapter/gh: an adapter, which only wiring may import"}
	if got := findingLines(importFindings(records, fixtureModule)); !slices.Equal(got, want) {
		t.Errorf("findings on an escaped adapter import:\n got %q\nwant %q", got, want)
	}
}

// TestRealTreeImports applies the rule to the module itself, and logs the allowed list.
func TestRealTreeImports(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("standard packages a package outside the four adapters may import: %s", strings.Join(allowedStd, " "))
	t.Logf("and %s alone may import %s", bridgeFile, bridgeImport)
	if !slices.ContainsFunc(records, func(r fileRecord) bool { return r.pkg == module+"/cmd/swarm" }) {
		t.Errorf("the walk of %s found no file of cmd/swarm", root)
	}
	for _, f := range importFindings(records, module) {
		t.Error(f)
	}
}

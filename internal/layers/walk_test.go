package layers

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

// The kinds of import an importRecord can have.
const (
	importPlain = "plain"
	importDot   = "dot"
	importBlank = "blank"
)

// fileRecord is what the walk records for one non-test .go file. The layer checks read these
// records and nothing else, so a later check never edits this file.
type fileRecord struct {
	pkg       string // the package's import path
	class     layer  // the package's layer, from classify
	path      string // the file's slash path relative to the root
	imports   []importRecord
	selectors []selectorRecord
}

// importRecord is one import of a file.
type importRecord struct {
	path string // the import path, unquoted
	name string // the local name: the explicit one, else the package's name; "." or "_" for a dot or blank import
	kind string // importPlain, importDot or importBlank
	line int
}

// selectorRecord is one selector X.Name whose X is an identifier spelled as one of the file's
// import names. It counts as a use of the import even where a local variable shadows that name, so
// the checks fail closed.
type selectorRecord struct {
	path   string // the import path X names
	name   string // the selected name
	line   int
	called bool // X.Name is the function of a call; false where it is only passed or read
}

// isSource reports whether name is a file packages counts: a .go file that is not a test and does
// not start with . or _.
func isSource(name string) bool {
	return strings.HasSuffix(name, ".go") && !strings.HasSuffix(name, "_test.go") &&
		!strings.HasPrefix(name, ".") && !strings.HasPrefix(name, "_")
}

// parsedFile is one file the walk parsed, before its records are made.
type parsedFile struct {
	pkg, rel string
	class    layer
	ast      *ast.File
}

// walk parses every non-test .go file of every package under root, the directory of the module
// named module, and returns one record per file, in packages' order and then by file name. It
// parses each file alone, so build tags are ignored and every file counts.
func walk(root, module string) ([]fileRecord, error) {
	pkgs, err := packages(root, module)
	if err != nil {
		return nil, err
	}
	fset := token.NewFileSet()
	var parsed []parsedFile
	pkgName := map[string]string{} // import path to package name, for module imports
	for _, pkg := range pkgs {
		rel := relTo(module, pkg)
		class, err := classify(rel)
		if err != nil {
			return nil, err
		}
		entries, err := os.ReadDir(filepath.Join(root, filepath.FromSlash(rel)))
		if err != nil {
			return nil, err
		}
		for _, e := range entries {
			if !e.Type().IsRegular() || !isSource(e.Name()) {
				continue
			}
			fileRel := path.Join(rel, e.Name())
			f, err := parser.ParseFile(fset, filepath.Join(root, filepath.FromSlash(fileRel)), nil, parser.SkipObjectResolution)
			if err != nil {
				return nil, err
			}
			pkgName[pkg] = f.Name.Name
			parsed = append(parsed, parsedFile{pkg: pkg, rel: fileRel, class: class, ast: f})
		}
	}
	records := make([]fileRecord, 0, len(parsed))
	for _, p := range parsed {
		records = append(records, record(fset, p, pkgName))
	}
	return records, nil
}

// record makes one file's record. pkgName gives the package name of each module package.
func record(fset *token.FileSet, p parsedFile, pkgName map[string]string) fileRecord {
	r := fileRecord{pkg: p.pkg, class: p.class, path: p.rel}
	byName := map[string]string{} // local name to import path
	for _, spec := range p.ast.Imports {
		imp := importRecord{path: spec.Path.Value, kind: importPlain, line: fset.Position(spec.Pos()).Line}
		// Decoded, so an escape cannot hide a path from the checks. A literal that does not decode
		// stays as written, quotes and all, which no rule allows.
		if p, err := strconv.Unquote(spec.Path.Value); err == nil {
			imp.path = p
		}
		switch {
		case spec.Name == nil:
			imp.name = defaultName(imp.path, pkgName)
		case spec.Name.Name == ".":
			imp.name, imp.kind = ".", importDot
		case spec.Name.Name == "_":
			imp.name, imp.kind = "_", importBlank
		default:
			imp.name = spec.Name.Name
		}
		if imp.kind == importPlain {
			byName[imp.name] = imp.path
		}
		r.imports = append(r.imports, imp)
	}
	called := map[*ast.SelectorExpr]bool{}
	ast.Inspect(p.ast, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.CallExpr:
			if sel, ok := callee(n.Fun).(*ast.SelectorExpr); ok {
				called[sel] = true
			}
		case *ast.SelectorExpr:
			x, ok := n.X.(*ast.Ident)
			if !ok {
				return true
			}
			if imp, ok := byName[x.Name]; ok {
				r.selectors = append(r.selectors, selectorRecord{
					path: imp, name: n.Sel.Name, line: fset.Position(n.Pos()).Line, called: called[n],
				})
			}
		}
		return true
	})
	return r
}

// callee is the function a call's fun names: fun without its parentheses and its type arguments, so
// slices.Clone[[]int](xs) calls slices.Clone.
func callee(fun ast.Expr) ast.Expr {
	for {
		switch f := ast.Unparen(fun).(type) {
		case *ast.IndexExpr:
			fun = f.X
		case *ast.IndexListExpr:
			fun = f.X
		default:
			return f
		}
	}
}

// defaultName is the name a plain import binds: the package's own name for a module package the
// walk parsed, else the path's last element, skipping a /vN major-version suffix.
func defaultName(imp string, pkgName map[string]string) string {
	if name, ok := pkgName[imp]; ok {
		return name
	}
	elems := strings.Split(imp, "/")
	last := elems[len(elems)-1]
	if len(elems) > 1 && len(last) > 1 && last[0] == 'v' && strings.Trim(last[1:], "0123456789") == "" {
		last = elems[len(elems)-2]
	}
	return last
}

// fixtureModule is the module path the fixture trees under testdata/ are walked as: they have no
// go.mod.
const fixtureModule = "example.com/m"

// walkFixture walks the fixture tree testdata/<dir> as fixtureModule.
func walkFixture(t *testing.T, dir string) []fileRecord {
	t.Helper()
	records, err := walk(filepath.Join("testdata", filepath.FromSlash(dir)), fixtureModule)
	if err != nil {
		t.Fatal(err)
	}
	return records
}

// TestWalkRecords asserts every field of the walk's record for one fixture file, written out here.
func TestWalkRecords(t *testing.T) {
	const file = "internal/clean/clean.go"
	var got *fileRecord
	for _, r := range walkFixture(t, "imports/clean") {
		if r.path == file {
			got = &r
		}
	}
	if got == nil {
		t.Fatalf("the walk has no record for %s", file)
	}
	m := fixtureModule
	want := fileRecord{
		pkg:   m + "/internal/clean",
		class: layer{kind: kindRules},
		path:  file,
		imports: []importRecord{
			{path: "fmt", name: "fmt", kind: importPlain, line: 6},
			{path: "path/filepath", name: "fp", kind: importPlain, line: 7},
			{path: "slices", name: "slices", kind: importPlain, line: 8},
			{path: "strings", name: "_", kind: importBlank, line: 9},
			{path: "unicode/utf8", name: "utf8", kind: importPlain, line: 10},
			{path: m + "/internal/iface", name: "iface", kind: importPlain, line: 12},
		},
		selectors: []selectorRecord{
			{path: m + "/internal/iface", name: "Store", line: 16, called: false},
			{path: "fmt", name: "Sprint", line: 20, called: true},
			{path: "path/filepath", name: "Join", line: 20, called: true},
			{path: "path/filepath", name: "Base", line: 24, called: false},
			{path: "unicode/utf8", name: "RuneLen", line: 28, called: true},
			{path: "fmt", name: "Errorf", line: 33, called: true},
			{path: "slices", name: "Index", line: 38, called: true},
			{path: "slices", name: "Clone", line: 38, called: true},
		},
	}
	if !reflect.DeepEqual(*got, want) {
		t.Errorf("the record for %s:\n got %s\nwant %s", file, dump(*got), dump(want))
	}
}

// dump prints a record with its field names, so a failure shows which field differs.
func dump(r fileRecord) string {
	return fmt.Sprintf("%+v", struct {
		Pkg, Class, Path string
		Imports          []importRecord
		Selectors        []selectorRecord
	}{r.pkg, r.class.String(), r.path, r.imports, r.selectors})
}

// TestDefaultName pins the name a plain import binds when the walk did not parse its package.
func TestDefaultName(t *testing.T) {
	for imp, want := range map[string]string{
		"fmt": "fmt", "path/filepath": "filepath", "math/rand/v2": "rand", "example.com/x/v10": "x", "v2": "v2",
		"example.com/vx": "vx",
	} {
		if got := defaultName(imp, nil); got != want {
			t.Errorf("defaultName(%q) = %q, want %q", imp, got, want)
		}
	}
	if got := defaultName("example.com/m/a", map[string]string{"example.com/m/a": "other"}); got != "other" {
		t.Errorf("defaultName of a parsed package = %q, want its package name other", got)
	}
}

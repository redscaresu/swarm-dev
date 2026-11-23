package layers

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
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

// fileRecord is what the walk records for one non-test .go file. The checks read these records
// and nothing else, so a later check never edits this file.
type fileRecord struct {
	pkg       string // the package's import path
	class     layer  // the package's layer, from classify
	path      string // the file's slash path relative to the root
	imports   []importRecord
	selectors []selectorRecord
	calls     []callRecord
	lits      []litRecord
	comments  map[int]string         // line to the text of the last // comment on it, without the // and outer space
	consts    map[string]constRecord // the file's package-level constants by name
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

// callRecord is one call whose function, through callee, is a selector X.Name with X spelled as one
// of the file's plain import names. As with selectorRecord, a local variable that shadows X does
// not stop it counting.
type callRecord struct {
	path string // the import path X names
	name string // the selected name
	line int    // the line of X.Name
	args []ast.Expr
	fn   ast.Node // the innermost *ast.FuncDecl or *ast.FuncLit around the call; nil at package level
	top  ast.Node // the outermost one, whose declarations constValue reads: fn when they do not nest
}

// litRecord is one composite literal whose type, through callee, is a selector X.Name with X
// spelled as one of the file's plain import names, as exec.Cmd{} or &exec.Cmd{}.
type litRecord struct {
	path string // the import path X names
	name string // the selected type's name
	line int
}

// constRecord is one package-level constant.
type constRecord struct {
	value string // the constant's string value, set when str is
	str   bool   // the constant's value is one string literal, written or repeated from the line above
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
// parses each file alone, with its comments, so build tags are ignored and every file counts.
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
			f, err := parser.ParseFile(fset, filepath.Join(root, filepath.FromSlash(fileRel)), nil, parser.SkipObjectResolution|parser.ParseComments)
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
	var stack []ast.Node // the nodes from the file down to the one visited
	ast.Inspect(p.ast, func(n ast.Node) bool {
		if n == nil {
			stack = stack[:len(stack)-1]
			return true
		}
		stack = append(stack, n)
		switch n := n.(type) {
		case *ast.CallExpr:
			sel, ok := callee(n.Fun).(*ast.SelectorExpr)
			if !ok {
				return true
			}
			called[sel] = true
			if imp, ok := importedBy(sel, byName); ok {
				fn, top := funcs(stack)
				r.calls = append(r.calls, callRecord{
					path: imp, name: sel.Sel.Name, line: fset.Position(sel.Pos()).Line, args: n.Args, fn: fn, top: top,
				})
			}
		case *ast.CompositeLit:
			if sel, ok := callee(n.Type).(*ast.SelectorExpr); ok {
				if imp, ok := importedBy(sel, byName); ok {
					r.lits = append(r.lits, litRecord{path: imp, name: sel.Sel.Name, line: fset.Position(n.Pos()).Line})
				}
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
	for _, group := range p.ast.Comments {
		for _, c := range group.List {
			if text, ok := strings.CutPrefix(c.Text, "//"); ok {
				if r.comments == nil {
					r.comments = map[int]string{}
				}
				r.comments[fset.Position(c.Slash).Line] = strings.TrimSpace(text)
			}
		}
	}
	r.consts = fileConsts(p.ast)
	return r
}

// importedBy gives the import path of sel's X, where X is an identifier spelled as one of the plain
// import names in byName.
func importedBy(sel *ast.SelectorExpr, byName map[string]string) (string, bool) {
	x, ok := sel.X.(*ast.Ident)
	if !ok {
		return "", false
	}
	imp, ok := byName[x.Name]
	return imp, ok
}

// funcs gives the innermost and the outermost *ast.FuncDecl or *ast.FuncLit on stack, nil for both
// when there is none.
func funcs(stack []ast.Node) (inner, outer ast.Node) {
	for _, n := range stack {
		switch n.(type) {
		case *ast.FuncDecl, *ast.FuncLit:
			if outer == nil {
				outer = n
			}
			inner = n
		}
	}
	return inner, outer
}

// fileConsts gives f's package-level constants by name, nil when it has none. A constant with no
// value of its own repeats the expression of the line above it in its group, as Go does.
func fileConsts(f *ast.File) map[string]constRecord {
	var consts map[string]constRecord
	for _, decl := range f.Decls {
		gen, ok := decl.(*ast.GenDecl)
		if !ok || gen.Tok != token.CONST {
			continue
		}
		var values []ast.Expr
		for _, spec := range gen.Specs {
			vs := spec.(*ast.ValueSpec)
			if len(vs.Values) > 0 {
				values = vs.Values
			}
			for i, name := range vs.Names {
				if name.Name == "_" {
					continue
				}
				var k constRecord
				if i < len(values) {
					k.value, k.str = stringLit(values[i])
				}
				if consts == nil {
					consts = map[string]constRecord{}
				}
				consts[name.Name] = k
			}
		}
	}
	return consts
}

// stringLit gives the value of e when e is one string literal.
func stringLit(e ast.Expr) (string, bool) {
	lit, ok := ast.Unparen(e).(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	v, err := strconv.Unquote(lit.Value)
	return v, err == nil
}

// constIndex holds the module's package-level constants: import path to name to constant. walk's
// records are all of the module's own packages, so no standard-library package is in it.
type constIndex map[string]map[string]constRecord

// indexConsts makes the constIndex of records.
func indexConsts(records []fileRecord) constIndex {
	ix := constIndex{}
	for _, r := range records {
		for name, k := range r.consts {
			if ix[r.pkg] == nil {
				ix[r.pkg] = map[string]constRecord{}
			}
			ix[r.pkg][name] = k
		}
	}
	return ix
}

// constValue reports whether e, an expression in call c of file f, names a module constant: an
// identifier naming a constant of f's own package, or a selector X.Name where X is one of f's plain
// imports of a module package and Name is a constant of it. The identifier, or X, must be declared
// nowhere in c's outermost function, as a variable, parameter or anything else, so a shadowed name
// fails closed. It gives the constant's record, whose value is set when it is one string literal.
func (ix constIndex) constValue(f fileRecord, c callRecord, e ast.Expr) (constRecord, bool) {
	var pkg, name, local string
	switch e := ast.Unparen(e).(type) {
	case *ast.Ident:
		pkg, name, local = f.pkg, e.Name, e.Name
	case *ast.SelectorExpr:
		x, ok := e.X.(*ast.Ident)
		if !ok {
			return constRecord{}, false
		}
		imp, ok := plainImport(f, x.Name)
		if !ok {
			return constRecord{}, false
		}
		pkg, name, local = imp, e.Sel.Name, x.Name
	default:
		return constRecord{}, false
	}
	if c.top != nil && declares(c.top, local) {
		return constRecord{}, false
	}
	k, ok := ix[pkg][name]
	return k, ok
}

// plainImport gives the path of f's plain import named name.
func plainImport(f fileRecord, name string) (string, bool) {
	for _, imp := range f.imports {
		if imp.kind == importPlain && imp.name == name {
			return imp.path, true
		}
	}
	return "", false
}

// declares reports whether fn declares name anywhere in it: a parameter, result, receiver, type
// parameter, variable, constant or type, or a field or method of a type it writes. It counts more
// than Go's scopes do, so a check that reads it fails closed.
func declares(fn ast.Node, name string) bool {
	found := false
	ast.Inspect(fn, func(n ast.Node) bool {
		var idents []ast.Expr
		switch n := n.(type) {
		case *ast.Field:
			for _, id := range n.Names {
				idents = append(idents, id)
			}
		case *ast.ValueSpec:
			for _, id := range n.Names {
				idents = append(idents, id)
			}
		case *ast.TypeSpec:
			idents = append(idents, n.Name)
		case *ast.AssignStmt:
			if n.Tok == token.DEFINE {
				idents = n.Lhs
			}
		case *ast.RangeStmt:
			if n.Tok == token.DEFINE {
				idents = append(idents, n.Key, n.Value)
			}
		}
		for _, e := range idents {
			if id, ok := e.(*ast.Ident); ok && id.Name == name {
				found = true
			}
		}
		return !found
	})
	return found
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
	wantCalls := []callView{
		{Path: "fmt", Name: "Sprint", Line: 20, Args: []string{"fp.Join(a, b)"}, Fn: "Join", Top: "Join"},
		{Path: "path/filepath", Name: "Join", Line: 20, Args: []string{"a", "b"}, Fn: "Join", Top: "Join"},
		{Path: "unicode/utf8", Name: "RuneLen", Line: 28, Args: []string{"r"}, Fn: "Width", Top: "Width"},
		{Path: "fmt", Name: "Errorf", Line: 33, Args: []string{`"x"`}, Fn: "Shadow", Top: "Shadow"},
		{Path: "slices", Name: "Index", Line: 38, Args: []string{"slices.Clone[[]int](xs)", "1"}, Fn: "Generic", Top: "Generic"},
		{Path: "slices", Name: "Clone", Line: 38, Args: []string{"xs"}, Fn: "Generic", Top: "Generic"},
	}
	if calls := viewCalls(got.calls); !reflect.DeepEqual(calls, wantCalls) {
		t.Errorf("the calls of %s:\n got %+v\nwant %+v", file, calls, wantCalls)
	}
	want.comments = map[int]string{
		1:  "Package clean is a rules package whose every import is allowed. TestWalkRecords asserts its",
		2:  "records field by field, so keep its lines where they are.",
		15: "S is a store.",
		18: "Join joins a and b.",
		23: "Base is filepath.Base, passed as a value rather than called.",
		26: "Width is the bytes r takes.",
		31: "Shadow's fmt is a parameter, but the walk counts fmt.Errorf as the fmt import's.",
		36: "Generic calls slices' functions with their type arguments written out.",
	}
	rest := *got
	rest.calls = nil
	if !reflect.DeepEqual(rest, want) {
		t.Errorf("the record for %s:\n got %s\nwant %s", file, dump(rest), dump(want))
	}
}

// dump prints a record but its calls with its field names, so a failure shows which field differs.
func dump(r fileRecord) string {
	return fmt.Sprintf("%+v", struct {
		Pkg, Class, Path string
		Imports          []importRecord
		Selectors        []selectorRecord
		Lits             []litRecord
		Comments         map[int]string
		Consts           map[string]constRecord
	}{r.pkg, r.class.String(), r.path, r.imports, r.selectors, r.lits, r.comments, r.consts})
}

// callView is a callRecord written out: each argument by its source as types.ExprString prints it,
// which elides a composite literal's elements, and each function by funcName.
type callView struct {
	Path, Name string
	Line       int
	Args       []string
	Fn, Top    string
}

// viewCalls writes calls out as callViews.
func viewCalls(calls []callRecord) []callView {
	var views []callView
	for _, c := range calls {
		v := callView{Path: c.path, Name: c.name, Line: c.line, Fn: funcName(c.fn), Top: funcName(c.top)}
		for _, a := range c.args {
			v.Args = append(v.Args, types.ExprString(a))
		}
		views = append(views, v)
	}
	return views
}

// funcName names a callRecord's function: a declaration by its name, a literal by its signature as
// types.ExprString prints it, and "" for none.
func funcName(n ast.Node) string {
	switch n := n.(type) {
	case *ast.FuncDecl:
		return n.Name.Name
	case *ast.FuncLit:
		return types.ExprString(n)
	case nil:
		return ""
	}
	return fmt.Sprintf("%T", n)
}

// TestWalkCalls asserts the calls, composite literals, comments and constants the walk records for
// the fixture testdata/walk, and what constValue makes of each call's first argument, all written
// out here.
func TestWalkCalls(t *testing.T) {
	records := walkFixture(t, "walk")
	byPath := map[string]fileRecord{}
	for _, r := range records {
		byPath[r.path] = r
	}
	m := fixtureModule
	const lit = "(func() *exec.Cmd literal)"

	consts := byPath["internal/consts/consts.go"]
	wantConsts := map[string]constRecord{"Pattern": {value: "^a+$", str: true}, "Level": {}}
	if !reflect.DeepEqual(consts.consts, wantConsts) {
		t.Errorf("the constants of consts.go: got %+v, want %+v", consts.consts, wantConsts)
	}

	f, ok := byPath["internal/rules/rules.go"]
	if !ok {
		t.Fatal("the walk has no record for internal/rules/rules.go")
	}
	wantCalls := []callView{
		{Path: "regexp", Name: "MustCompile", Line: 20, Args: []string{"local"}},
		{Path: "regexp", Name: "MustCompile", Line: 26, Args: []string{"consts.Pattern"}, Fn: "Match", Top: "Match"},
		{Path: "regexp", Name: "QuoteMeta", Line: 27, Args: []string{"s"}, Fn: "Match", Top: "Match"},
		{Path: "regexp", Name: "MustCompile", Line: 28, Args: []string{"consts.Name"}, Fn: "Match", Top: "Match"},
		{Path: "time", Name: "Duration", Line: 29, Args: []string{"consts.Level"}, Fn: "Match", Top: "Match"},
		{Path: "time", Name: "Sleep", Line: 36, Args: []string{"time.Second"}, Fn: lit, Top: "Later"},
		{Path: "regexp", Name: "MustCompile", Line: 37, Args: []string{"first"}, Fn: lit, Top: "Later"},
		{Path: "regexp", Name: "MustCompile", Line: 38, Args: []string{"(again)"}, Fn: lit, Top: "Later"},
	}
	if got := viewCalls(f.calls); !reflect.DeepEqual(got, wantCalls) {
		t.Errorf("the calls of rules.go:\n got %+v\nwant %+v", got, wantCalls)
	}
	wantLits := []litRecord{{path: "os/exec", name: "Cmd", line: 39}, {path: "os/exec", name: "Cmd", line: 43}}
	if !reflect.DeepEqual(f.lits, wantLits) {
		t.Errorf("the composite literals of rules.go: got %+v, want %+v", f.lits, wantLits)
	}
	wantComments := map[int]string{
		1:  "Package rules holds the calls TestWalkCalls asserts, so keep its lines where they are.",
		12: "a trailing comment",
		20: "the last comment on its line",
		24: "Match calls in a function.",
		33: "Later calls in a function literal, under a parameter that shadows the constant first.",
	}
	if !reflect.DeepEqual(f.comments, wantComments) {
		t.Errorf("the comments of rules.go:\n got %+v\nwant %+v", f.comments, wantComments)
	}
	wantFileConsts := map[string]constRecord{
		"local": {value: "b+", str: true}, "first": {value: "x", str: true}, "again": {value: "x", str: true}, "count": {},
	}
	if !reflect.DeepEqual(f.consts, wantFileConsts) {
		t.Errorf("the constants of rules.go: got %+v, want %+v", f.consts, wantFileConsts)
	}

	// constValue of each call's first argument, by the call's line.
	type value struct {
		k  constRecord
		ok bool
	}
	wantValues := map[int]value{
		20: {constRecord{value: "b+", str: true}, true},   // a constant of the file's own package, at package level
		26: {constRecord{value: "^a+$", str: true}, true}, // a constant of another module package
		27: {},                                            // a parameter
		28: {},                                            // a variable of another module package
		29: {constRecord{}, true},                         // a constant that is no string
		36: {},                                            // a standard-library constant, no module one
		37: {},                                            // a constant shadowed by the outer function's parameter
		38: {constRecord{value: "x", str: true}, true},    // a repeated constant, in parentheses
	}
	ix := indexConsts(records)
	if pkgs := len(ix); pkgs != 2 || ix[m+"/internal/rules"] == nil || ix[m+"/internal/consts"] == nil {
		t.Errorf("the constIndex has %d packages, want rules and consts: %+v", pkgs, ix)
	}
	for _, c := range f.calls {
		k, ok := ix.constValue(f, c, c.args[0])
		if got, want := (value{k, ok}), wantValues[c.line]; got != want {
			t.Errorf("constValue of %s on line %d = %+v, want %+v", types.ExprString(c.args[0]), c.line, got, want)
		}
	}
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

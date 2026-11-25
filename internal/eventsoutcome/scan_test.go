package eventsoutcome

import (
	"bytes"
	"context"
	"fmt"
	"go/ast"
	"go/constant"
	"go/importer"
	"go/parser"
	"go/token"
	"go/types"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The outcome scan: no Go code of the module reads events.tsv's outcome column (row[4]) but this
// package. The column may end in a key=value tail, so a raw read of it turns false once a writer adds
// fields; a reader calls Outcome or Fields instead. It is the Go side of tests/outcome_scan_test.sh,
// which keeps scanning bin/.
//
// The scan flags every index expression whose index, and every slice expression whose start, go/types
// gives as the integer constant outcomeCol, whatever the operand is and wherever it came from: a
// strings.Split row, an encoding/csv record, a []string parameter, a struct's field. A named constant
// equal to outcomeCol counts; a variable does not. The one operand it passes is a string, whose [4]
// is a byte of one value (a date's "-"), never a column. It does not follow where a row comes from, so a
// read of another file's fifth column (findings.tsv, agents.tsv) ends its line with
// `// outcome-scan: ok <reason>`, the reason naming the file it reads.

// moduleRoot is the module's root, relative to this package's directory.
const moduleRoot = "../.."

// modulePath is the module's import path, as go.mod names it.
const modulePath = "github.com/redscaresu/swarm-dev"

// ownPackage is this package's import path, the one package the scan skips.
const ownPackage = modulePath + "/internal/eventsoutcome"

// scanOK is the opt-out: a // comment on the read's line saying outcome-scan: ok and a reason.
var scanOK = regexp.MustCompile(`^//\s*outcome-scan:\s*ok\s+\S`)

// goListTimeout bounds the one go list run that finds the export data of every import.
const goListTimeout = 5 * time.Minute

// target is one package the scan reads: its import path and its parsed files.
type target struct {
	path  string
	files []*ast.File
}

// parseTarget parses every non-test .go file in dir, with comments.
// The files are named by their absolute paths, so a finding can name its file relative to the root.
func parseTarget(fset *token.FileSet, path, dir string) (target, error) {
	t := target{path: path}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return t, err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return t, err
	}
	for _, e := range entries {
		name := e.Name()
		if !e.Type().IsRegular() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") ||
			strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_") {
			continue
		}
		f, err := parser.ParseFile(fset, filepath.Join(dir, name), nil, parser.ParseComments)
		if err != nil {
			return t, err
		}
		t.files = append(t.files, f)
	}
	return t, nil
}

// exportData runs go list once, from the module root, for the compiled export data of each import
// path in imports and every package they import, by import path.
func exportData(imports []string) (map[string]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), goListTimeout)
	defer cancel()
	args := append([]string{"list", "-export", "-deps", "-f", "{{.ImportPath}}\t{{.Export}}"}, imports...)
	cmd := exec.CommandContext(ctx, "go", args...)
	cmd.Dir = moduleRoot
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("go list -export: %w: %s", err, stderr.String())
	}
	export := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		path, file, _ := strings.Cut(line, "\t")
		export[path] = file
	}
	return export, nil
}

// scan type-checks each target and returns one "file:line: text" line per raw read of the outcome
// column, the file relative to moduleRoot, in the targets' order and then in source order. Imports
// come from their compiled export data. A type error fails the scan, since a scan of code go/types
// could not read would pass reads it never saw.
func scan(fset *token.FileSet, targets []target) ([]string, error) {
	var imports []string
	for _, t := range targets {
		for _, f := range t.files {
			for _, spec := range f.Imports {
				imp, err := strconv.Unquote(spec.Path.Value)
				if err != nil {
					return nil, err
				}
				if imp != "unsafe" && !slices.Contains(imports, imp) {
					imports = append(imports, imp)
				}
			}
		}
	}
	slices.Sort(imports)
	export, err := exportData(imports)
	if err != nil {
		return nil, err
	}
	imp := importer.ForCompiler(fset, "gc", func(path string) (io.ReadCloser, error) {
		file, ok := export[path]
		if !ok || file == "" {
			return nil, fmt.Errorf("go list gave no export data for %s", path)
		}
		return os.Open(file)
	})
	root, err := filepath.Abs(moduleRoot)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, t := range targets {
		info := &types.Info{Types: map[ast.Expr]types.TypeAndValue{}}
		conf := types.Config{Importer: imp}
		if _, err := conf.Check(t.path, fset, t.files, info); err != nil {
			return nil, fmt.Errorf("type-check %s: %w", t.path, err)
		}
		for _, f := range t.files {
			out = append(out, fileFindings(fset, root, f, info)...)
		}
	}
	return out, nil
}

// fileFindings returns the raw reads of the outcome column in f: every index whose index, and every
// slice whose start, is the constant outcomeCol, on a line without the opt-out. Each names its file
// relative to root, the module's absolute root.
func fileFindings(fset *token.FileSet, root string, f *ast.File, info *types.Info) []string {
	ok := map[int]bool{} // the lines with the opt-out
	for _, g := range f.Comments {
		for _, c := range g.List {
			if scanOK.MatchString(c.Text) {
				ok[fset.Position(c.Slash).Line] = true
			}
		}
	}
	var out []string
	ast.Inspect(f, func(n ast.Node) bool {
		var at token.Pos
		var col ast.Expr
		var x ast.Expr // the operand
		switch e := n.(type) {
		case *ast.IndexExpr:
			at, col, x = e.Lbrack, e.Index, e.X
		case *ast.SliceExpr:
			at, col, x = e.Lbrack, e.Low, e.X
		}
		if col == nil || !isOutcomeCol(info.Types[col].Value) || isString(info.Types[x].Type) {
			return true
		}
		pos := fset.Position(at)
		if !ok[pos.Line] {
			rel, err := filepath.Rel(root, pos.Filename)
			if err != nil {
				rel = pos.Filename
			}
			out = append(out, fmt.Sprintf("%s:%d: %s", filepath.ToSlash(rel), pos.Line, types.ExprString(n.(ast.Expr))))
		}
		return true
	})
	return out
}

// isOutcomeCol reports whether v is the integer constant outcomeCol; a nil v is no constant.
func isOutcomeCol(v constant.Value) bool {
	return v != nil && v.Kind() == constant.Int && constant.Compare(v, token.EQL, constant.MakeInt64(outcomeCol))
}

// isString reports whether t is a string type, a named one too; a nil t is not.
func isString(t types.Type) bool {
	if t == nil {
		return false
	}
	b, ok := types.Unalias(t).Underlying().(*types.Basic)
	return ok && b.Info()&types.IsString != 0
}

// modulePackages is the import path of every package of the module with a non-test .go file, sorted,
// skipping testdata and directories starting with . or _, as the go tool does.
func modulePackages(t *testing.T) []string {
	t.Helper()
	var pkgs []string
	err := filepath.WalkDir(moduleRoot, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		name := d.Name()
		if d.IsDir() {
			if p != moduleRoot && (name == "testdata" || strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_")) {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			return nil
		}
		rel, err := filepath.Rel(moduleRoot, filepath.Dir(p))
		if err != nil {
			return err
		}
		pkg := strings.TrimSuffix(modulePath+"/"+filepath.ToSlash(rel), "/.")
		if !slices.Contains(pkgs, pkg) {
			pkgs = append(pkgs, pkg)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(pkgs)
	return pkgs
}

// pkgDir is the directory of the module package path, relative to this package.
func pkgDir(path string) string {
	rel := strings.TrimPrefix(strings.TrimPrefix(path, modulePath), "/")
	return filepath.Join(moduleRoot, filepath.FromSlash(rel))
}

// TestOutcomeScanModule fails each raw read of the outcome column in the module's code outside this
// package. Its control: the walk must reach cmd/swarm, the command, and this package, which it leaves out.
func TestOutcomeScanModule(t *testing.T) {
	pkgs := modulePackages(t)
	if !slices.Contains(pkgs, modulePath+"/cmd/swarm") || !slices.Contains(pkgs, ownPackage) {
		t.Fatalf("the module walk found %v, without cmd/swarm or %s", pkgs, ownPackage)
	}
	fset := token.NewFileSet()
	var targets []target
	for _, pkg := range pkgs {
		if pkg == ownPackage {
			continue
		}
		tg, err := parseTarget(fset, pkg, pkgDir(pkg))
		if err != nil {
			t.Fatal(err)
		}
		targets = append(targets, tg)
	}
	got, err := scan(fset, targets)
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range got {
		t.Errorf("%s: reads events.tsv's outcome column raw; call eventsoutcome.Outcome or Fields, "+
			"or end the line with // outcome-scan: ok <reason>, naming the file it reads", line)
	}
}

// TestOutcomeScanFixtures runs the scan over testdata/scan, where each bad_*.go file holds one read the
// scan must fail and each good_*.go file reads in a way it must pass.
func TestOutcomeScanFixtures(t *testing.T) {
	const dir = "internal/eventsoutcome/testdata/scan/"
	fset := token.NewFileSet()
	tg, err := parseTarget(fset, ownPackage+"/testdata/scan", filepath.Join("testdata", "scan"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := scan(fset, []target{tg})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		dir + "bad_bytes.go:8: f[4]",
		dir + "bad_const.go:7: r[col]",
		dir + "bad_csv.go:12: rec[4]",
		dir + "bad_field.go:10: e.cols[4]",
		dir + "bad_noreason.go:5: f[4]",
		dir + "bad_param.go:5: row[4]",
		dir + "bad_slice.go:5: r[4:]",
		dir + "bad_split.go:8: f[4]",
		dir + "bad_split_call.go:7: strings.Split(l, \"\\t\")[4]",
	}
	if !slices.Equal(got, want) {
		t.Errorf("findings:\n got  %q\n want %q", got, want)
	}
}

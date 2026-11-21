package layers

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/adapter/gh"
	"github.com/redscaresu/swarm-dev/internal/adapter/git"
	"github.com/redscaresu/swarm-dev/internal/adapter/herdr"
	"github.com/redscaresu/swarm-dev/internal/adapter/store"
	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The kinds of layer a package can be in.
const (
	kindWiring     = "wiring"
	kindInterfaces = "interfaces"
	kindAdapter    = "adapter"
	kindClock      = "clock"
	kindRules      = "rules"
)

// The module-relative paths classify reads.
const (
	cmdDir     = "cmd"
	ifaceDir   = "internal/iface"
	adapterDir = "internal/adapter"
	clockDir   = "internal/clock"
)

// adapterOf maps each adapter package to the interface it implements, by the interface's name in
// internal/iface. TestAdapterTableMatchesTree checks it against the real types.
var adapterOf = map[string]string{
	adapterDir + "/herdr": "AgentRunner",
	adapterDir + "/gh":    "CodeHost",
	adapterDir + "/git":   "Repo",
	adapterDir + "/store": "Store",
}

// layer is the class of one package: its kind and, for an adapter, the interface it implements.
type layer struct {
	kind  string
	iface string
}

func (l layer) String() string {
	if l.kind == kindAdapter {
		return l.iface + "'s adapter"
	}
	return l.kind
}

// under reports whether the module-relative path rel is dir or a package below it.
func under(rel, dir string) bool {
	return rel == dir || strings.HasPrefix(rel, dir+"/")
}

// classify gives the package at rel, a slash path relative to the module root ("" for the root
// itself), its layer. A package under internal/adapter/ that is not under one of the four adapters
// is an error, as is internal/adapter itself: each interface has one implementation. Every package
// no other rule names is a rules package, so a new package is held to the rules until it is named.
func classify(rel string) (layer, error) {
	switch {
	case under(rel, cmdDir):
		return layer{kind: kindWiring}, nil
	case rel == ifaceDir:
		return layer{kind: kindInterfaces}, nil
	case rel == clockDir:
		return layer{kind: kindClock}, nil
	case under(rel, adapterDir):
		for dir, name := range adapterOf {
			if under(rel, dir) {
				return layer{kind: kindAdapter, iface: name}, nil
			}
		}
		return layer{}, fmt.Errorf("%s is under %s/ but under none of its four adapters: each interface has one implementation", rel, adapterDir)
	}
	return layer{kind: kindRules}, nil
}

// packages lists the import path of every package under root, the directory of the module named
// module: every directory with a non-test .go file, sorted. As the go tool does, it skips testdata/
// and every directory or file whose name starts with . or _.
func packages(root, module string) ([]string, error) {
	var pkgs []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		name := d.Name()
		if d.IsDir() {
			if path != root && (name == "testdata" || strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_")) {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") ||
			strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_") {
			return nil
		}
		rel, err := filepath.Rel(root, filepath.Dir(path))
		if err != nil {
			return err
		}
		pkg := module
		if rel != "." {
			pkg = module + "/" + filepath.ToSlash(rel)
		}
		if !slices.Contains(pkgs, pkg) {
			pkgs = append(pkgs, pkg)
		}
		return nil
	})
	slices.Sort(pkgs)
	return pkgs, err
}

// relTo is pkg's path relative to module: "" for the module itself.
func relTo(module, pkg string) string {
	if pkg == module {
		return ""
	}
	return strings.TrimPrefix(pkg, module+"/")
}

// moduleRoot finds the module's root above the test's directory and reads its module line.
func moduleRoot(t *testing.T) (root, module string) {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		data, err := os.ReadFile(filepath.Join(dir, "go.mod"))
		if err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if m, ok := strings.CutPrefix(strings.TrimSpace(line), "module "); ok {
					return dir, strings.TrimSpace(m)
				}
			}
			t.Fatalf("%s/go.mod has no module line", dir)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("no go.mod above the test's directory")
		}
		dir = parent
	}
}

// TestClassify asserts each class on paths written out here, not taken from the table, so a change
// to classify or adapterOf goes red.
func TestClassify(t *testing.T) {
	for _, c := range []struct{ rel, want string }{
		{"cmd/swarm", "wiring"},
		{"cmd/other/x", "wiring"},
		{"internal/iface", "interfaces"},
		{"internal/adapter/herdr", "AgentRunner's adapter"},
		{"internal/adapter/herdr/x", "AgentRunner's adapter"},
		{"internal/adapter/gh", "CodeHost's adapter"},
		{"internal/adapter/gh/x", "CodeHost's adapter"},
		{"internal/adapter/git", "Repo's adapter"},
		{"internal/adapter/git/x", "Repo's adapter"},
		{"internal/adapter/store", "Store's adapter"},
		{"internal/adapter/store/x", "Store's adapter"},
		{"internal/clock", "clock"},
		{"internal/board", "rules"},
		{"internal/guard/x", "rules"},
		{"internal/layers", "rules"},
		{"internal/iface/x", "rules"},
		{"internal/clock/x", "rules"},
		{"internal/clockx", "rules"},
		{"cmdx", "rules"},
		{"", "rules"},
	} {
		got, err := classify(c.rel)
		if err != nil {
			t.Errorf("classify(%q): %v, want %s", c.rel, err, c.want)
		} else if got.String() != c.want {
			t.Errorf("classify(%q) = %s, want %s", c.rel, got, c.want)
		}
	}
	for _, rel := range []string{"internal/adapter/other", "internal/adapter/other/x", "internal/adapter/ghx", "internal/adapter"} {
		if got, err := classify(rel); err == nil {
			t.Errorf("classify(%q) = %s, want an error: each interface has one adapter", rel, got)
		}
	}
}

// TestAdapterTableMatchesTree checks adapterOf against the real packages by reflection, not by text:
// each entry's interface is a type in internal/iface, its package holds a type that implements it,
// and the table has no entry beyond the four.
func TestAdapterTableMatchesTree(t *testing.T) {
	_, module := moduleRoot(t)
	adapters := []struct{ iface, impl reflect.Type }{
		{reflect.TypeFor[iface.AgentRunner](), reflect.TypeFor[herdr.Runner]()},
		{reflect.TypeFor[iface.CodeHost](), reflect.TypeFor[gh.Host]()},
		{reflect.TypeFor[iface.Repo](), reflect.TypeFor[git.Repo]()},
		{reflect.TypeFor[iface.Store](), reflect.TypeFor[store.Files]()},
	}
	seen := map[string]bool{}
	for _, r := range adapters {
		dir := relTo(module, r.impl.PkgPath())
		seen[dir] = true
		if want := module + "/" + ifaceDir; r.iface.PkgPath() != want {
			t.Errorf("%s is in %s, want %s", r.iface.Name(), r.iface.PkgPath(), want)
		}
		if !r.impl.Implements(r.iface) {
			t.Errorf("%s does not implement iface.%s", r.impl, r.iface.Name())
		}
		if got, ok := adapterOf[dir]; !ok {
			t.Errorf("adapterOf has no entry for %s, which implements iface.%s", dir, r.iface.Name())
		} else if got != r.iface.Name() {
			t.Errorf("adapterOf[%q] = %s, but its type implements iface.%s", dir, got, r.iface.Name())
		}
	}
	for dir, name := range adapterOf {
		if !seen[dir] {
			t.Errorf("adapterOf names %s as %s's adapter, but no real adapter type is in that package", dir, name)
		}
	}
}

// TestPackagesSkipsWhatTheGoToolSkips runs packages on a tree made here.
func TestPackagesSkipsWhatTheGoToolSkips(t *testing.T) {
	root := t.TempDir()
	for _, f := range []string{
		"root.go", "a/x.go", "a/x_test.go", "a/b/y.go", "testonly/x_test.go", "nogo/x.txt",
		"testdata/c/x.go", ".hidden/x.go", "_skip/x.go", "a/_skip.go", "underscore/_x.go",
	} {
		path := filepath.Join(root, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("package x\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, err := packages(root, "example.com/m")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"example.com/m", "example.com/m/a", "example.com/m/a/b"}
	if !slices.Equal(got, want) {
		t.Errorf("packages() = %q, want %q", got, want)
	}
}

// TestRealTreeClasses classifies every package of the module and logs one "covers <pkg> as <class>"
// line for each; the CI step that prints the layer checks greps that text, so keep it stable.
func TestRealTreeClasses(t *testing.T) {
	root, module := moduleRoot(t)
	pkgs, err := packages(root, module)
	if err != nil {
		t.Fatal(err)
	}
	covered := map[string]bool{}
	for _, pkg := range pkgs {
		rel := relTo(module, pkg)
		l, err := classify(rel)
		if err != nil {
			t.Errorf("%v", err)
			continue
		}
		covered[rel] = true
		shown := rel
		if shown == "" {
			shown = "."
		}
		t.Logf("covers %s as %s", shown, l)
	}
	for _, rel := range []string{
		"cmd/swarm", "internal/iface", "internal/adapter/herdr", "internal/adapter/gh",
		"internal/adapter/git", "internal/adapter/store", "internal/clock", "internal/layers",
	} {
		if !covered[rel] {
			t.Errorf("the walk of %s found no package %s", root, rel)
		}
	}
}

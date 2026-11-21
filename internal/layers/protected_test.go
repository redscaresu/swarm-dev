package layers

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// protectedDirs are the four packages that hold the guard, merge, release and agent-environment
// rules, each a module-relative directory with its trailing slash. They are OWN_PROTECTED's Go paths
// (bin/lib/board.sh), which ship-gates fixed: the paths only the user merges in this repo. Keep the
// two in step.
var protectedDirs = []string{"internal/guard/", "internal/merge/", "internal/release/", "internal/agentenv/"}

// shortList is every module package a protected package may import beside the four: the interfaces
// with the store's types, and the clock. Each must be a package in the tree.
var shortList = []string{ifaceDir, clockDir}

// isProtected reports whether the package at the module-relative path rel is one of the four or a
// package below one, matched as OWN_PROTECTED matches a path: a prefix with its trailing slash, so
// internal/merge/x is protected and internal/guardian is not. It ignores the case of letters, as
// protected_hold does, so a rule cannot leave the check by spelling its package internal/Merge.
func isProtected(rel string) bool {
	low := strings.ToLower(rel) + "/"
	return slices.ContainsFunc(protectedDirs, func(dir string) bool { return strings.HasPrefix(low, dir) })
}

// mayImport reports whether a protected package may import the module package at rel: one of the
// four as spelled (an import gets no case folding, so the looser reading never lets one through), or
// an entry of shortList.
func mayImport(rel string) bool {
	return slices.Contains(shortList, rel) ||
		slices.ContainsFunc(protectedDirs, func(dir string) bool { return strings.HasPrefix(rel+"/", dir) })
}

// protectedFindings applies the protected rule to the walk's records of the module named module: a
// file in a protected package fails on each module import that mayImport refuses, of any kind. Its
// standard imports are importFindings' to judge.
func protectedFindings(records []fileRecord, module string) []importFinding {
	why := "a module package outside the four protected packages and off the short list (" + strings.Join(shortList, " ") + ")"
	var found []importFinding
	for _, r := range records {
		if !isProtected(relTo(module, r.pkg)) {
			continue
		}
		for _, imp := range r.imports {
			if inModule(imp.path, module) && !mayImport(relTo(module, imp.path)) {
				found = append(found, importFinding{file: r.path, line: imp.line, pkg: r.pkg, imp: imp.path, why: why})
			}
		}
	}
	return found
}

// protectedPackages lists the protected packages the walk found, module-relative, in its order.
func protectedPackages(records []fileRecord, module string) []string {
	var pkgs []string
	for _, r := range records {
		if rel := relTo(module, r.pkg); isProtected(rel) && !slices.Contains(pkgs, rel) {
			pkgs = append(pkgs, rel)
		}
	}
	return pkgs
}

// missingShortList names each shortList entry that is not a package the walk found.
func missingShortList(records []fileRecord, module string) []string {
	var missing []string
	for _, rel := range shortList {
		if !slices.ContainsFunc(records, func(r fileRecord) bool { return relTo(module, r.pkg) == rel }) {
			missing = append(missing, fmt.Sprintf("the short list names %s, which is not a package in the tree", rel))
		}
	}
	return missing
}

// The finding's reason, written out here and not built from shortList, so a change to the list goes
// red.
const protectedWhy = "a module package outside the four protected packages and off the short list (internal/iface internal/clock)"

// TestProtectedFixtures asserts the exact findings on testdata/protected/tree/: internal/merge/x fails
// on its imports of internal/board and internal/guardian. internal/guard imports the interfaces, the
// clock, internal/release and the standard library and passes; internal/guardian imports
// internal/board and is not protected; a test file of internal/merge/x imports internal/board and is
// exempt.
func TestProtectedFixtures(t *testing.T) {
	const x = fixtureModule + "/internal/merge/x"
	want := []string{
		"internal/merge/x/x.go:6: " + x + " imports " + fixtureModule + "/internal/board: " + protectedWhy,
		"internal/merge/x/x.go:7: " + x + " imports " + fixtureModule + "/internal/guardian: " + protectedWhy,
	}
	records := walkFixture(t, "protected/tree")
	if got := findingLines(protectedFindings(records, fixtureModule)); !slices.Equal(got, want) {
		t.Errorf("findings on protected/tree:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}
	if got, want := protectedPackages(records, fixtureModule), []string{"internal/guard", "internal/merge/x", "internal/release"}; !slices.Equal(got, want) {
		t.Errorf("protected packages in protected/tree = %q, want %q", got, want)
	}
	if got := missingShortList(records, fixtureModule); len(got) != 0 {
		t.Errorf("protected/tree has internal/iface and internal/clock, but: %s", strings.Join(got, "; "))
	}
}

// TestProtectedShortListMissing: a short-list entry that is not a package in the tree is an error.
// testdata/protected/noclock/ has internal/iface and no internal/clock.
func TestProtectedShortListMissing(t *testing.T) {
	want := []string{"the short list names internal/clock, which is not a package in the tree"}
	if got := missingShortList(walkFixture(t, "protected/noclock"), fixtureModule); !slices.Equal(got, want) {
		t.Errorf("missing short-list entries in protected/noclock:\n got %q\nwant %q", got, want)
	}
}

// TestProtectedAnyCase: a package spelled internal/Merge/x is protected, as protected_hold holds it in
// any case, while an import of internal/Release passes only as spelled and so fails. The tree is made
// here, as a checked-in internal/Merge/ beside protected/tree's internal/merge/ would read as one
// directory on a case-insensitive checkout.
func TestProtectedAnyCase(t *testing.T) {
	root := t.TempDir()
	src := "package x\n\nimport (\n\t_ \"" + fixtureModule + "/internal/Release\"\n\t_ \"" + fixtureModule + "/internal/board\"\n)\n"
	dir := filepath.Join(root, "internal", "Merge", "x")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "x.go"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	records, err := walk(root, fixtureModule)
	if err != nil {
		t.Fatal(err)
	}
	const x = fixtureModule + "/internal/Merge/x"
	want := []string{
		"internal/Merge/x/x.go:4: " + x + " imports " + fixtureModule + "/internal/Release: " + protectedWhy,
		"internal/Merge/x/x.go:5: " + x + " imports " + fixtureModule + "/internal/board: " + protectedWhy,
	}
	if got := findingLines(protectedFindings(records, fixtureModule)); !slices.Equal(got, want) {
		t.Errorf("findings on internal/Merge/x:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}
}

// TestRealTreeProtected applies the protected rule to the module itself. It logs the four, the short
// list and the protected packages the tree has, and fails on a short-list entry the tree lacks.
func TestRealTreeProtected(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("protected packages, matched as OWN_PROTECTED matches them: %s", strings.Join(protectedDirs, " "))
	t.Logf("module packages a protected package may import beside the four (the short list): %s", strings.Join(shortList, " "))
	if pkgs := protectedPackages(records, module); len(pkgs) == 0 {
		t.Log("protected packages in the tree: none exists yet, so the rule has nothing to check")
	} else {
		t.Logf("protected packages in the tree: %s", strings.Join(pkgs, " "))
	}
	for _, m := range missingShortList(records, module) {
		t.Error(m)
	}
	for _, f := range protectedFindings(records, module) {
		t.Error(f)
	}
}

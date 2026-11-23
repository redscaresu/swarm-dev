package layers

import (
	"cmp"
	"fmt"
	"go/ast"
	"go/token"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// regexpPath is the import path of the standard regexp package, whose QuoteMeta makes a variable
// safe to put in a pattern.
const regexpPath = "regexp"

// regexpJudged gives, for each import path, the functions whose pattern the rule judges and the
// index of that pattern among each one's arguments. A glob is the Go form of the bash check's
// [[ == <glob> ]] shape.
var regexpJudged = map[string]map[string]int{
	regexpPath: {
		"Compile": 0, "CompilePOSIX": 0, "MustCompile": 0, "MustCompilePOSIX": 0,
		"Match": 0, "MatchString": 0, "MatchReader": 0,
	},
	"regexp/syntax": {"Parse": 0},
	"path":          {"Match": 0},
	"path/filepath": {"Match": 0, "Glob": 0},
	"io/fs":         {"Glob": 1},
}

// regexpOK is the comment that marks a line as right: loose-match: ok, then a reason.
var regexpOK = regexp.MustCompile(`^loose-match:\s*ok\s+\S`)

// The reasons a regexpFinding gives, each with its fix.
const (
	regexpWhyPattern = "the pattern is not string literals, module constants and regexp.QuoteMeta calls joined by +; " +
		"pass a variable through regexp.QuoteMeta, or end the line with // loose-match: ok <reason>"
	regexpWhyValue = "passed as a value, which hides its calls from this check; call it by name, " +
		"or end the line with // loose-match: ok <reason>"
	regexpWhyDot = "a dot import, which hides its calls from this check; import it by name"
)

// regexpRule is the rule as go test -v logs it.
const regexpRule = "in every non-test .go file, the pattern of a regexp compile or match, regexp/syntax.Parse, " +
	"path.Match, filepath.Match, filepath.Glob or fs.Glob is string literals, module constants and " +
	"regexp.QuoteMeta calls joined by +; none of them is passed as a value, and none of their packages " +
	"is dot-imported; a line that is right ends with // loose-match: ok <reason>"

// regexpFinding is one loose pattern the rule fails.
type regexpFinding struct {
	file string // the file's slash path relative to the root
	line int
	pkg  string // the package of the file
	use  string // what the file does: "calls regexp.MustCompile", "uses regexp.MustCompile" or "dot-imports regexp"
	why  string
}

func (f regexpFinding) String() string {
	return fmt.Sprintf("%s:%d: %s %s: %s", f.file, f.line, f.pkg, f.use, f.why)
}

// regexpCheck applies the rule to the walk's records. It gives the findings, by file and line, and
// the calls it allows as "file:line: calls path.Name", with ", by its ok comment" where only the
// comment allows one.
func regexpCheck(records []fileRecord) (found []regexpFinding, allowed []string) {
	ix := indexConsts(records)
	for _, r := range records {
		fail := func(line int, use, why string) {
			if !regexpOK.MatchString(r.comments[line]) {
				found = append(found, regexpFinding{file: r.path, line: line, pkg: r.pkg, use: use, why: why})
			}
		}
		for _, imp := range r.imports {
			if _, judged := regexpJudged[imp.path]; judged && imp.kind == importDot {
				fail(imp.line, "dot-imports "+imp.path, regexpWhyDot)
			}
		}
		for _, s := range r.selectors {
			if _, judged := regexpJudged[s.path][s.name]; judged && !s.called {
				fail(s.line, "uses "+s.path+"."+s.name, regexpWhyValue)
			}
		}
		for _, c := range r.calls {
			arg, judged := regexpJudged[c.path][c.name]
			if !judged {
				continue
			}
			use := "calls " + c.path + "." + c.name
			switch {
			case arg < len(c.args) && regexpTight(ix, r, c, c.args[arg]):
				allowed = append(allowed, fmt.Sprintf("%s:%d: %s", r.path, c.line, use))
			case regexpOK.MatchString(r.comments[c.line]):
				allowed = append(allowed, fmt.Sprintf("%s:%d: %s, by its ok comment", r.path, c.line, use))
			default:
				fail(c.line, use, regexpWhyPattern)
			}
		}
	}
	slices.SortStableFunc(found, func(a, b regexpFinding) int {
		return cmp.Or(strings.Compare(a.file, b.file), cmp.Compare(a.line, b.line))
	})
	return found, allowed
}

// regexpTight reports whether e, a pattern in call c of file f, is string literals, module
// constants and regexp.QuoteMeta calls, joined by + and parenthesised at will.
func regexpTight(ix constIndex, f fileRecord, c callRecord, e ast.Expr) bool {
	switch e := ast.Unparen(e).(type) {
	case *ast.BasicLit:
		return e.Kind == token.STRING
	case *ast.BinaryExpr:
		return e.Op == token.ADD && regexpTight(ix, f, c, e.X) && regexpTight(ix, f, c, e.Y)
	case *ast.CallExpr:
		return regexpQuoteMeta(f, c, e)
	}
	_, ok := ix.constValue(f, c, e)
	return ok
}

// regexpQuoteMeta reports whether call, inside c of file f, calls regexp.QuoteMeta through one of
// f's plain imports of regexp, under a name c's outermost function does not declare.
func regexpQuoteMeta(f fileRecord, c callRecord, call *ast.CallExpr) bool {
	sel, ok := callee(call.Fun).(*ast.SelectorExpr)
	if !ok || sel.Sel.Name != "QuoteMeta" {
		return false
	}
	x, ok := sel.X.(*ast.Ident)
	if !ok {
		return false
	}
	imp, ok := plainImport(f, x.Name)
	return ok && imp == regexpPath && (c.top == nil || !declares(c.top, x.Name))
}

// regexpLines is each finding as its String, in the walk's order.
func regexpLines(found []regexpFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// TestRegexpFixtures asserts the exact findings on the fixture trees under testdata/regexp/,
// written out here. bad/ has one loose pattern of each shape, and clean/ has the tight ones and an
// ok comment with its reason: it has no finding, and every call it makes is allowed.
func TestRegexpFixtures(t *testing.T) {
	m := fixtureModule
	rules := m + "/internal/rules"
	at := func(file string, line int, use, why string) string {
		return fmt.Sprintf("internal/rules/%s:%d: %s %s: %s", file, line, rules, use, why)
	}
	want := []string{
		at("alias.go", 7, "calls regexp.MatchString", regexpWhyPattern),
		at("bad.go", 16, "calls regexp.MustCompile", regexpWhyPattern),
		at("bad.go", 17, "calls regexp.MustCompile", regexpWhyPattern),
		at("bad.go", 18, "calls regexp.MustCompile", regexpWhyPattern),
		at("bad.go", 19, "calls path.Match", regexpWhyPattern),
		at("bad.go", 20, "calls path/filepath.Match", regexpWhyPattern),
		at("bad.go", 21, "calls path/filepath.Glob", regexpWhyPattern),
		at("bad.go", 22, "calls io/fs.Glob", regexpWhyPattern),
		at("bad.go", 23, "calls regexp/syntax.Parse", regexpWhyPattern),
		at("bad.go", 24, "calls regexp.MustCompile", regexpWhyPattern),
		at("bad.go", 32, "calls regexp.MustCompile", regexpWhyPattern),
		at("bad.go", 36, "uses regexp.MustCompile", regexpWhyValue),
		at("dot.go", 3, "dot-imports regexp", regexpWhyDot),
	}
	found, _ := regexpCheck(walkFixture(t, "regexp/bad"))
	if got := regexpLines(found); !slices.Equal(got, want) {
		t.Errorf("findings on regexp/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}

	found, allowed := regexpCheck(walkFixture(t, "regexp/clean"))
	if len(found) != 0 {
		t.Errorf("findings on regexp/clean, want none:\n%s", strings.Join(regexpLines(found), "\n"))
	}
	wantAllowed := []string{
		"internal/rules/clean.go:15: calls regexp.MustCompile",
		"internal/rules/clean.go:16: calls regexp.MustCompile",
		"internal/rules/clean.go:17: calls regexp.MustCompile",
		"internal/rules/clean.go:18: calls regexp.MustCompile",
		"internal/rules/clean.go:19: calls regexp.MustCompile",
		"internal/rules/clean.go:20: calls path/filepath.Glob",
		"internal/rules/clean.go:21: calls io/fs.Glob",
		"internal/rules/clean.go:22: calls regexp.MustCompile, by its ok comment",
	}
	if !slices.Equal(allowed, wantAllowed) {
		t.Errorf("the calls regexp/clean makes, which the rule allows:\n got %s\nwant %s",
			strings.Join(allowed, "\n     "), strings.Join(wantAllowed, "\n     "))
	}
}

// TestRealTreeRegexp applies the rule to the module itself. It logs the rule and each call it
// allows, and fails unless it allows internal/clock/clock.go:22, a raw literal.
func TestRealTreeRegexp(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("loose-match rule: %s", regexpRule)
	found, allowed := regexpCheck(records)
	for _, a := range allowed {
		t.Logf("allows %s", a)
	}
	const clockPattern = "internal/clock/clock.go:22: calls regexp.MustCompile"
	if !slices.Contains(allowed, clockPattern) {
		t.Errorf("the rule does not allow %s, a raw literal; it allows %q", clockPattern, allowed)
	}
	for _, f := range found {
		t.Error(f)
	}
}

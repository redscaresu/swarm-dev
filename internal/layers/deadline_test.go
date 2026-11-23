package layers

import (
	"fmt"
	"go/ast"
	"go/token"
	"slices"
	"strings"
	"testing"
)

// The import paths the deadline rule reads.
const (
	deadlineExecPath    = "os/exec"
	deadlineContextPath = "context"
)

// deadlinePrograms are the programs that can wait forever, by their last path element, as
// tests/timeouts_test.sh bounds them in the bash. Go is stricter: every start of one needs a deadline,
// not only the calls of it that block.
var deadlinePrograms = []string{"gh", "herdr", "curl"}

// deadlineWrappers run the next argument as a program, so the bash check sees a call behind them
// (tests/timeouts_test.sh:4-5). A start of one needs a deadline whatever it runs.
var deadlineWrappers = []string{"env", "nohup", "time", "command", "exec", "nice", "xargs"}

// deadlineShells run a script given with -c, which can call anything. A start of one with a literal
// -c argument needs a deadline; a start of one with a script path needs none.
var deadlineShells = []string{"sh", "bash", "zsh", "dash"}

// deadlineMakers are the context functions whose context has a deadline.
var deadlineMakers = []string{"WithTimeout", "WithDeadline"}

// deadlineFinding is one start, or one import, the rule fails.
type deadlineFinding struct {
	file string // the file's slash path relative to the root
	line int
	pkg  string // the package of the file
	use  string // what the file does: "starts gh with exec.Command", "dot-imports os/exec" and the like
	why  string // why that fails, and the fix
}

func (f deadlineFinding) String() string {
	return fmt.Sprintf("%s:%d: %s %s: %s", f.file, f.line, f.pkg, f.use, f.why)
}

// deadlineStart is one exec.Command or exec.CommandContext call the rule judged.
type deadlineStart struct {
	file string
	line int
	prog string // the program's last path element, "-c" added for a shell given a script that way; "" when the check cannot tell
	need bool   // the start needs a deadline
}

func (s deadlineStart) String() string {
	switch {
	case s.prog == "":
		return fmt.Sprintf("%s:%d: starts a program the check cannot tell", s.file, s.line)
	case s.need:
		return fmt.Sprintf("%s:%d: starts %s, which needs a deadline", s.file, s.line, s.prog)
	}
	return fmt.Sprintf("%s:%d: starts %s, which needs no deadline", s.file, s.line, s.prog)
}

// The fixes a deadlineFinding names, and the reasons it gives.
const (
	deadlineEscape     = "or end the line with // no-timeout: <reason>"
	deadlineFixContext = "make it in the function that starts the program, once, as the first name on the left of := from context.WithTimeout or context.WithDeadline, and set it nowhere else; " + deadlineEscape
	deadlineWhyCommand = "it can wait forever; start it with exec.CommandContext under a context made with context.WithTimeout or context.WithDeadline in the function that starts it, " + deadlineEscape
	deadlineWhyProgram = "the program is neither a string literal nor a module constant, so the check cannot tell what it runs; name it with one, " + deadlineEscape
	deadlineWhyDot     = "a dot import, which hides its names from this check; import it by name"
	deadlineWhyReason  = "a no-timeout comment with no reason; say after the colon why the start needs no deadline"

	deadlineCtxExpr    = "its context is an expression, not a variable"
	deadlineCtxParam   = "its context is a parameter of its function"
	deadlineCtxNone    = "its context is not made in its function"
	deadlineCtxTwice   = "its context is declared more than once in its function"
	deadlineCtxMaker   = "its context is not made with context.WithTimeout or context.WithDeadline"
	deadlineCtxSet     = "its context is set again after it is made"
	deadlineCtxOutside = "its context is made after the start, or in a block the start is not in"
)

// deadlineFindings applies the deadline rule to the walk's records, in every package, adapters and
// wiring included. A dot import of os/exec or of context fails. Each exec.Command and
// exec.CommandContext call, under any import name, is judged by deadlineJudge, unless its line ends
// with // no-timeout: <reason>; that comment with no reason fails. It also gives every start it judged.
func deadlineFindings(records []fileRecord) ([]deadlineFinding, []deadlineStart) {
	ix := indexConsts(records)
	var found []deadlineFinding
	var starts []deadlineStart
	for _, r := range records {
		for _, imp := range r.imports {
			if imp.kind == importDot && (imp.path == deadlineExecPath || imp.path == deadlineContextPath) {
				found = append(found, deadlineFinding{file: r.path, line: imp.line, pkg: r.pkg, use: "dot-imports " + imp.path, why: deadlineWhyDot})
			}
		}
		for _, c := range r.calls {
			if c.path != deadlineExecPath || (c.name != "Command" && c.name != "CommandContext") {
				continue
			}
			s, use, why := deadlineJudge(ix, r, c)
			starts = append(starts, s)
			fail := func(use, why string) {
				found = append(found, deadlineFinding{file: r.path, line: c.line, pkg: r.pkg, use: use, why: why})
			}
			if text, ok := r.comments[c.line]; ok && (text == "no-timeout" || strings.HasPrefix(text, "no-timeout:")) {
				if strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(text, "no-timeout"), ":")) == "" {
					fail("has // no-timeout", deadlineWhyReason)
				}
				continue
			}
			if why != "" {
				fail(use, why)
			}
		}
	}
	return found, starts
}

// deadlineJudge judges one start: the program, Command's first argument and CommandContext's second,
// must be a string literal or a module constant. A program on deadlinePrograms or deadlineWrappers,
// or a shell on deadlineShells with a literal -c argument, needs a deadline, and has one only through
// CommandContext under a context deadlineContextWhy accepts. It gives the start, and the finding's
// use and why, a why of "" when the start passes.
func deadlineJudge(ix constIndex, r fileRecord, c callRecord) (s deadlineStart, use, why string) {
	s = deadlineStart{file: r.path, line: c.line}
	at := 0
	if c.name == "CommandContext" {
		at = 1
	}
	if len(c.args) <= at {
		return s, "starts no program with exec." + c.name, deadlineWhyProgram
	}
	prog, ok := deadlineString(ix, r, c, c.args[at])
	if !ok {
		return s, "starts a program with exec." + c.name, deadlineWhyProgram
	}
	s.prog = prog[strings.LastIndex(prog, "/")+1:]
	switch {
	case slices.Contains(deadlinePrograms, s.prog), slices.Contains(deadlineWrappers, s.prog):
		s.need = true
	case slices.Contains(deadlineShells, s.prog) && deadlineDashC(ix, r, c, c.args[at+1:]):
		s.prog += " -c"
		s.need = true
	}
	use = "starts " + s.prog + " with exec." + c.name
	switch {
	case !s.need:
		return s, use, ""
	case c.name == "Command":
		return s, use, deadlineWhyCommand
	}
	if bad := deadlineContextWhy(r, c); bad != "" {
		return s, use, bad + "; " + deadlineFixContext
	}
	return s, use, ""
}

// deadlineString gives e's value when e is a string literal or names a module constant whose value
// is one.
func deadlineString(ix constIndex, r fileRecord, c callRecord, e ast.Expr) (string, bool) {
	if v, ok := stringLit(e); ok {
		return v, true
	}
	k, ok := ix.constValue(r, c, e)
	return k.value, ok && k.str
}

// deadlineDashC reports whether any string literal or module constant anywhere in args is a short
// option cluster with c in it ("-c", "-ec"), so a -c inside append([]string{"-c", s}, more...) counts.
func deadlineDashC(ix constIndex, r fileRecord, c callRecord, args []ast.Expr) bool {
	found := false
	for _, a := range args {
		ast.Inspect(a, func(n ast.Node) bool {
			if e, ok := n.(ast.Expr); ok {
				if v, ok := deadlineString(ix, r, c, e); ok && len(v) > 1 && v[0] == '-' && v[1] != '-' && strings.Contains(v, "c") {
					found = true
				}
			}
			return !found
		})
	}
	return found
}

// deadlineContextWhy gives why the context of CommandContext call c fails, "" when it passes. It
// passes only as an identifier that c's own function declares once, as the first name on the left
// of := from context.WithTimeout or context.WithDeadline, before the start and in a block that holds
// it, sets nowhere else and takes its address nowhere, and has as no parameter. Every declaration
// of the name in the function counts, nested function literals' too, so the check fails closed.
func deadlineContextWhy(r fileRecord, c callRecord) string {
	id, ok := ast.Unparen(c.args[0]).(*ast.Ident)
	if !ok {
		return deadlineCtxExpr
	}
	name := id.Name
	if c.fn == nil {
		return deadlineCtxNone
	}
	var sig []*ast.FieldList
	switch fn := c.fn.(type) {
	case *ast.FuncDecl:
		sig = []*ast.FieldList{fn.Recv, fn.Type.TypeParams, fn.Type.Params, fn.Type.Results}
	case *ast.FuncLit:
		sig = []*ast.FieldList{fn.Type.Params, fn.Type.Results}
	}
	for _, list := range sig {
		if list != nil && slices.ContainsFunc(list.List, func(f *ast.Field) bool { return deadlineNamed(name, deadlineIdents(f.Names)...) }) {
			return deadlineCtxParam
		}
	}
	decls, set := 0, false
	var made *ast.AssignStmt
	var madeIn ast.Node // the node that holds made: its scope
	var stack []ast.Node
	ast.Inspect(c.fn, func(n ast.Node) bool {
		if n == nil {
			stack = stack[:len(stack)-1]
			return true
		}
		switch n := n.(type) {
		case *ast.Field:
			decls += deadlineCount(name, deadlineIdents(n.Names)...)
		case *ast.ValueSpec:
			decls += deadlineCount(name, deadlineIdents(n.Names)...)
		case *ast.TypeSpec:
			decls += deadlineCount(name, n.Name)
		case *ast.RangeStmt:
			if n.Tok == token.DEFINE {
				decls += deadlineCount(name, n.Key, n.Value)
			} else if deadlineNamed(name, n.Key, n.Value) {
				set = true
			}
		case *ast.AssignStmt:
			switch {
			case n.Tok != token.DEFINE:
				set = set || deadlineNamed(name, n.Lhs...)
			case deadlineNamed(name, n.Lhs...):
				decls++
				made, madeIn = n, stack[len(stack)-1]
			}
		case *ast.UnaryExpr:
			set = set || (n.Op == token.AND && deadlineNamed(name, n.X))
		}
		stack = append(stack, n)
		return true
	})
	switch {
	case decls == 0:
		return deadlineCtxNone
	case decls > 1:
		return deadlineCtxTwice
	case made == nil || !deadlineMade(r, c, name, made):
		return deadlineCtxMaker
	case set:
		return deadlineCtxSet
	case made.End() > id.Pos() || id.Pos() > madeIn.End():
		return deadlineCtxOutside
	}
	return ""
}

// deadlineMade reports whether made puts name first on its left, from one call of context.WithTimeout
// or context.WithDeadline through a plain import of context that c's outermost function does not
// shadow.
func deadlineMade(r fileRecord, c callRecord, name string, made *ast.AssignStmt) bool {
	if len(made.Rhs) != 1 || !deadlineNamed(name, made.Lhs[0]) {
		return false
	}
	call, ok := ast.Unparen(made.Rhs[0]).(*ast.CallExpr)
	if !ok {
		return false
	}
	sel, ok := callee(call.Fun).(*ast.SelectorExpr)
	if !ok || !slices.Contains(deadlineMakers, sel.Sel.Name) {
		return false
	}
	x, ok := sel.X.(*ast.Ident)
	if !ok {
		return false
	}
	imp, ok := plainImport(r, x.Name)
	return ok && imp == deadlineContextPath && !declares(c.top, x.Name)
}

// deadlineIdents gives ids as expressions.
func deadlineIdents(ids []*ast.Ident) []ast.Expr {
	es := make([]ast.Expr, 0, len(ids))
	for _, id := range ids {
		es = append(es, id)
	}
	return es
}

// deadlineCount counts the identifiers in es spelled name, in parentheses or not, so (ctx) = x counts as a set.
func deadlineCount(name string, es ...ast.Expr) int {
	n := 0
	for _, e := range es {
		if id, ok := ast.Unparen(e).(*ast.Ident); ok && id.Name == name {
			n++
		}
	}
	return n
}

// deadlineNamed reports whether any of es is an identifier spelled name.
func deadlineNamed(name string, es ...ast.Expr) bool { return deadlineCount(name, es...) > 0 }

// deadlineLines is each finding as its String, in the walk's order.
func deadlineLines(found []deadlineFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// TestDeadlineFixtures asserts the exact findings on the fixture trees under testdata/deadline/,
// written out here. bad/ starts gh, curl, herdr, env and bash -c with exec.Command, a program from a
// variable, and gh with exec.CommandContext under each context the rule fails; it imports os/exec
// under an alias, dot-imports os/exec and context in an adapter, and has a no-timeout comment with
// no reason. clean/ starts gh and herdr under a WithTimeout and a WithDeadline context, bash with a
// script path, and gh on a line whose no-timeout comment gives its reason: it has no finding.
func TestDeadlineFixtures(t *testing.T) {
	rules := fixtureModule + "/internal/rules"
	at := func(file string, line int, use, why string) string {
		return fmt.Sprintf("internal/rules/%s:%d: %s %s: %s", file, line, rules, use, why)
	}
	ctx := func(line int, bad string) string {
		return at("context.go", line, "starts gh with exec.CommandContext", bad+"; "+deadlineFixContext)
	}
	gh := fixtureModule + "/internal/adapter/gh"
	want := []string{
		"internal/adapter/gh/gh.go:4: " + gh + " dot-imports context: " + deadlineWhyDot,
		"internal/adapter/gh/gh.go:5: " + gh + " dot-imports os/exec: " + deadlineWhyDot,
		at("alias.go", 6, "starts gh with exec.Command", deadlineWhyCommand),
		at("command.go", 13, "starts gh with exec.Command", deadlineWhyCommand),
		at("command.go", 14, "starts curl with exec.Command", deadlineWhyCommand),
		at("command.go", 15, "starts herdr with exec.Command", deadlineWhyCommand),
		at("command.go", 16, "starts env with exec.Command", deadlineWhyCommand),
		at("command.go", 17, "starts bash -c with exec.Command", deadlineWhyCommand),
		at("command.go", 18, "starts sh -c with exec.Command", deadlineWhyCommand),
		at("command.go", 23, "starts a program with exec.Command", deadlineWhyProgram),
		at("command.go", 28, "has // no-timeout", deadlineWhyReason),
		ctx(14, deadlineCtxExpr),
		ctx(19, deadlineCtxParam),
		ctx(26, deadlineCtxExpr),
		ctx(34, deadlineCtxSet),
		ctx(43, deadlineCtxTwice),
		ctx(52, deadlineCtxMaker),
		ctx(57, deadlineCtxNone),
		ctx(65, deadlineCtxOutside),
		ctx(73, deadlineCtxSet),
		ctx(81, deadlineCtxSet),
	}
	found, _ := deadlineFindings(walkFixture(t, "deadline/bad"))
	if got := deadlineLines(found); !slices.Equal(got, want) {
		t.Errorf("findings on deadline/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}

	found, starts := deadlineFindings(walkFixture(t, "deadline/clean"))
	if len(found) != 0 {
		t.Errorf("findings on deadline/clean, want none:\n%s", strings.Join(deadlineLines(found), "\n"))
	}
	wantStarts := []deadlineStart{
		{file: "internal/clean/clean.go", line: 18, prog: "gh", need: true},
		{file: "internal/clean/clean.go", line: 25, prog: "herdr", need: true},
		{file: "internal/clean/clean.go", line: 30, prog: "bash", need: false},
		{file: "internal/clean/clean.go", line: 35, prog: "gh", need: true},
	}
	if !slices.Equal(starts, wantStarts) {
		t.Errorf("the starts judged on deadline/clean:\n got %+v\nwant %+v", starts, wantStarts)
	}
}

// TestRealTreeDeadline applies the rule to the module itself. It logs the rule and each start it
// judged, fails when the walk finds no exec.Command or exec.CommandContext call, and asserts the
// bridge's start of bash with a script path is among them, judged as needing no deadline.
func TestRealTreeDeadline(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("Go is stricter than tests/timeouts_test.sh, which bounds only the calls that can wait forever: "+
		"every start of a program (%s), a wrapper (%s) or a shell given -c (%s) has its deadline where it starts, "+
		"through exec.CommandContext under a context its own function makes with context.WithTimeout or context.WithDeadline; "+
		"each finding names the fix",
		strings.Join(deadlinePrograms, ", "), strings.Join(deadlineWrappers, ", "), strings.Join(deadlineShells, ", "))
	found, starts := deadlineFindings(records)
	if len(starts) == 0 {
		t.Errorf("the walk of %s found no exec.Command or exec.CommandContext call", root)
	}
	for _, s := range starts {
		t.Logf("judged %s", s)
	}
	bridge := deadlineStart{file: "cmd/swarm/bridge.go", line: 36, prog: "bash", need: false}
	if !slices.Contains(starts, bridge) {
		t.Errorf("the starts judged do not include %s", bridge)
	}
	for _, f := range found {
		t.Error(f)
	}
}

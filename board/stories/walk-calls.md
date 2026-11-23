---
kind: code
status: blocked
epic: first-port
depends_on: [first-port-freeze-start]
needs: first-port-freeze-start (its **You:** steps: the freeze is on, so the epic may start)
touches: [internal/layers/walk_test.go:fileRecord, walk, record and TestWalkRecords, internal/layers/testdata/walk/, internal/layers/doc.go:package comment]
estimate_lines: 160
---

# The layer walk also records each call of an imported function with its arguments, each line's comment and each file's constants

Needs first-port-freeze-start's **You:** steps: the freeze is on. Shared support for go-check-regexp, go-check-deadlines and go-check-starts. internal/layers/ is a protected path (OWN_PROTECTED, bin/lib/board.sh:2546), so swarm.sh merge holds the PR for the user.
- The go_check rows of tests/loose_match_test.sh and tests/timeouts_test.sh (docs/port/tests.tsv:87,147) need a call's arguments and the comment on its line. The walk records neither: fileRecord holds only imports and selectors (internal/layers/walk_test.go:26-50), and walk parses with parser.SkipObjectResolution and no parser.ParseComments (:92). Checks read only its records (:24-25). So the walk is extended once here and three checks read the result (rules.md: fix the shared cause first), rather than each check writing its own parse.
- walk parses with parser.ParseComments too. fileRecord gains:
  calls: each call whose function, through callee, is a selector X.Name with X a plain import's name: the import path, the name, the line, the argument expressions, and the innermost *ast.FuncDecl or *ast.FuncLit around it (nil at package level);
  lits: each composite literal whose type is such a selector, as exec.Cmd{} or &exec.Cmd{}: the import path, the name and the line;
  comments: the text of the last // comment on each line;
  consts: the file's package-level constants, with the value of each that is one string literal.
- A helper, constValue, says whether an expression in a call names a module constant: an identifier of the file's own package, where the call's function declares no variable or parameter of that name, or a selector of a module import. It gives the constant's string value when it has one.
- TestWalkRecords (walk_test.go:200) asserts the new fields for its file: arguments by their printed source, the function by its name. A new TestWalkCalls asserts them on a new fixture testdata/walk/: a call in a function and in a function literal, a composite literal, a trailing comment, a constant from another package and a shadowed one.
- doc.go's first sentence says the package holds the Go checks over the module's code, in its tests only, of which the layer checks are one set. That stays true before and after the three checks merge, in any order.
- moduleRoot and packages are in classes_test.go:133 and :90. Every existing check and its test stays as it is.

**Done when:**
- (1) TestWalkRecords and TestWalkCalls pass, each value written out. (2) git diff shows no change to classes_test.go, imports_test.go, names_test.go, protected_test.go or time_test.go, and go test ./internal/layers/ passes. (3) On a copy of the worktree without .git, each of these turns TestWalkCalls red, and the FAIL lines are in the PR body: ParseComments dropped; the outermost function recorded in place of the innermost; a shadowed identifier taken as a constant; a selector of a standard-library import taken as a module constant. (4) gofmt -l . prints nothing, and go vet ./... and go test ./... pass. (5) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

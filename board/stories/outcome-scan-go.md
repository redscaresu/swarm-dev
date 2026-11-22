---
kind: code
status: later
epic: helpers-shared
depends_on: [go-events-outcome]
needs: go-events-outcome: the internal/eventsoutcome package, the only one the check lets read the column raw.
touches: [internal/eventsoutcome/scan_test.go, internal/eventsoutcome/testdata/scan]
estimate_lines: 200
---

# A Go check fails Go code that reads events.tsv's outcome column without the Go outcome parser

Needs internal/eventsoutcome from go-events-outcome, the one package allowed to read the column raw. This is tests.tsv's go_check for tests/outcome_scan_test.sh (docs/port/tests.tsv:107). A Go test in internal/eventsoutcome walks every non-test .go file of the module outside that package. It flags every index or slice whose index or start is the constant 4, whatever the operand is and wherever it came from: a strings.Split row, an encoding/csv record (on allowedStd, internal/layers/imports_test.go:17), a []string argument, a struct's field. It takes the constant from go/types, so a named constant equal to 4 counts and a variable does not. So the check does not follow where a row comes from: every fifth-column read goes through eventsoutcome or says why it need not. A line ending `// outcome-scan: ok <reason>`, the reason naming the file read, passes, as the bash scan's opt-out does (tests/outcome_scan_test.sh:17-19). The bash scan keeps scanning bin/. go/ast, go/parser and go/types are used only in the _test.go file, which the layer walk skips (internal/layers/walk_test.go:55). Fixtures are Go files under testdata/. Detection logic: under about 120 lines.

**Done when:**
- (1) The check passes on the module. (2) Fixture files fail it, each with file:line: f[4] == "ok" on a Split row; strings.Split(l, "\t")[4]; a csv.Reader record's [4]; a []string parameter's [4]; r[4:]; r[col] with const col = 4. A fixture with the opt-out comment passes, one calling eventsoutcome.Outcome passes, and one reading r[i] with a variable i passes. (3) It goes red when the check alone looks only at rows from strings.Split, and when it alone drops the named constant, each shown on a worktree copy without .git. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes

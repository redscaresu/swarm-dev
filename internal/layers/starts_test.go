package layers

import (
	"fmt"
	"path"
	"slices"
	"strings"
	"testing"
)

// startExecPath is the import path of os/exec, whose Command and CommandContext calls are the only
// process starts the module may make, as the deadline check judges each of them.
const startExecPath = "os/exec"

// startFuncs is, for each standard package other than os/exec that can start a process, the names
// that start one: os.StartProcess, syscall's own starts, and syscall's raw entry points, which take
// a trap number and so can run execve or fork. Any use fails, called or only passed.
var startFuncs = map[string][]string{
	"os":      {"StartProcess"},
	"syscall": {"Exec", "ForkExec", "StartProcess", "Syscall", "Syscall6", "Syscall9", "RawSyscall", "RawSyscall6", "SyscallN"},
}

// startDotPaths is every package whose dot import fails, since it hides the names above from this
// check.
var startDotPaths = []string{"os", startExecPath, "syscall"}

// startFinding is one process start the rule fails.
type startFinding struct {
	file string // the file's slash path relative to the root
	line int
	pkg  string // the package that starts the process
	use  string // what the file does, as "calls syscall.Exec" or "builds an exec.Cmd literal"
	why  string
}

func (f startFinding) String() string {
	return fmt.Sprintf("%s:%d: %s %s: %s", f.file, f.line, f.pkg, f.use, f.why)
}

// The reasons a startFinding gives.
const (
	startWhyStart = "a process start the deadline check does not judge; start one only with an exec.Command or exec.CommandContext call"
	startWhyDot   = "a dot import, which hides its names from this check"
)

// startFindings applies the rule to the walk's records, in every package, adapters and wiring
// included. It fails a dot import of a package in startDotPaths; a selector on one of startFuncs'
// names, under any import name; an exec.Cmd composite literal, with or without &; and
// exec.Command or exec.CommandContext used as a value, since a call through that value is no call
// the deadline check sees. exec.Cmd as a type passes. No comment lets a finding through.
func startFindings(records []fileRecord) []startFinding {
	var found []startFinding
	for _, r := range records {
		add := func(line int, use, why string) {
			found = append(found, startFinding{file: r.path, line: line, pkg: r.pkg, use: use, why: why})
		}
		for _, imp := range r.imports {
			if imp.kind == importDot && slices.Contains(startDotPaths, imp.path) {
				add(imp.line, "dot-imports "+imp.path, startWhyDot)
			}
		}
		for _, s := range r.selectors {
			name := path.Base(s.path) + "." + s.name
			switch {
			case slices.Contains(startFuncs[s.path], s.name) && s.called:
				add(s.line, "calls "+name, startWhyStart)
			case slices.Contains(startFuncs[s.path], s.name):
				add(s.line, "uses "+name, startWhyStart)
			case s.path == startExecPath && (s.name == "Command" || s.name == "CommandContext") && !s.called:
				add(s.line, "uses "+name+" as a value", startWhyStart)
			}
		}
		for _, l := range r.lits {
			if l.path == startExecPath && l.name == "Cmd" {
				add(l.line, "builds an exec.Cmd literal", startWhyStart)
			}
		}
	}
	return found
}

// startCalls lists, as "file:line: calls exec.X", each exec.Command and exec.CommandContext call in
// records: the starts the rule leaves to the deadline check.
func startCalls(records []fileRecord) []string {
	var calls []string
	for _, r := range records {
		for _, c := range r.calls {
			if c.path == startExecPath && (c.name == "Command" || c.name == "CommandContext") {
				calls = append(calls, fmt.Sprintf("%s:%d: calls exec.%s", r.path, c.line, c.name))
			}
		}
	}
	return calls
}

// startFindingLines is each finding as its String, in the walk's order.
func startFindingLines(found []startFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// TestStartsFixtures asserts the exact findings on the fixture trees under testdata/starts/, written
// out here. bad/ calls os.StartProcess and syscall's starts and passes each as a value, builds
// exec.Cmd literals with and without & and through an aliased os/exec, passes exec.Command and
// exec.CommandContext as values, and dot-imports os, os/exec and syscall, os/exec in an adapter.
// clean/ calls exec.Command and exec.CommandContext, takes *exec.Cmd as a parameter, declares an
// exec.Cmd variable and uses os and syscall names that start nothing: it has no finding.
func TestStartsFixtures(t *testing.T) {
	m := fixtureModule
	rules := m + "/internal/rules"
	var want []string
	for i, name := range []string{"os.StartProcess", "syscall.Exec", "syscall.ForkExec", "syscall.StartProcess", "syscall.Syscall", "syscall.RawSyscall"} {
		want = append(want, fmt.Sprintf("internal/rules/called.go:%d: %s calls %s: %s", 9+i, rules, name, startWhyStart))
	}
	want = append(want,
		"internal/adapter/herdr/herdr.go:3: "+m+"/internal/adapter/herdr dot-imports os/exec: "+startWhyDot,
		"internal/iface/iface.go:4: "+m+"/internal/iface dot-imports os: "+startWhyDot,
		"internal/iface/iface.go:5: "+m+"/internal/iface dot-imports syscall: "+startWhyDot,
		"internal/rules/lits.go:8: "+rules+" builds an exec.Cmd literal: "+startWhyStart,
		"internal/rules/lits.go:9: "+rules+" builds an exec.Cmd literal: "+startWhyStart,
		"internal/rules/lits.go:10: "+rules+" builds an exec.Cmd literal: "+startWhyStart,
		"internal/rules/passed.go:9: "+rules+" uses exec.Command as a value: "+startWhyStart,
		"internal/rules/passed.go:10: "+rules+" uses exec.CommandContext as a value: "+startWhyStart,
		"internal/rules/passed.go:11: "+rules+" uses os.StartProcess: "+startWhyStart,
		"internal/rules/passed.go:12: "+rules+" uses syscall.ForkExec: "+startWhyStart,
	)
	slices.Sort(want)
	got := startFindingLines(startFindings(walkFixture(t, "starts/bad")))
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Errorf("findings on starts/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}

	clean := walkFixture(t, "starts/clean")
	if len(clean) != 2 {
		t.Errorf("the walk of starts/clean found %d files, want 2: the rules package and the adapter", len(clean))
	}
	if got := startFindings(clean); len(got) != 0 {
		t.Errorf("findings on starts/clean, want none:\n%s", strings.Join(startFindingLines(got), "\n"))
	}
	wantCalls := []string{"internal/adapter/gh/gh.go:13: calls exec.CommandContext", "internal/adapter/gh/gh.go:18: calls exec.Command"}
	if got := startCalls(clean); !slices.Equal(got, wantCalls) {
		t.Errorf("the starts on starts/clean left to the deadline check:\n got %q\nwant %q", got, wantCalls)
	}
}

// TestRealTreeStarts applies the rule to the module itself. It logs the rule and each start it
// leaves to the deadline check, and fails unless the walk finds cmd/swarm/bridge.go's exec.Command
// call, so a walk that read nothing cannot pass.
func TestRealTreeStarts(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("a process starts only through an exec.Command or exec.CommandContext call, in every package; no comment lets another start through")
	const bridge = "cmd/swarm/bridge.go:36: calls exec.Command"
	calls := startCalls(records)
	for _, c := range calls {
		t.Logf("leaves %s to the deadline check", c)
	}
	if !slices.Contains(calls, bridge) {
		t.Errorf("the walk of %s did not find %s", root, bridge)
	}
	for _, f := range startFindings(records) {
		t.Error(f)
	}
}

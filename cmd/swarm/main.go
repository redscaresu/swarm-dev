// Command swarm is the Go port of bin/swarm.sh. It runs one entry of its table by dispatch name,
// inside the frame bin/swarm.sh hands it (frame.go), and hands a form still in bash back to swarm.sh
// (bridge.go). No command is ported yet. The table holds one helper entry, _require-trusted
// (trusted.go), which bash runs in place of a Python helper, and wrapper-fixture and _wrapper-fixture,
// for the wrapper's tests.
package main

import (
	"os"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// exitUsage is the exit code of a run that does nothing: a name with no entry, or an entry that needs
// the frame run without it.
const exitUsage = 2

func main() {
	c := &call{
		stdin:  os.Stdin,
		stdout: os.Stdout,
		stderr: os.Stderr,
		frame:  readFrame(os.Environ()),
		store:  store.Files{},
	}
	os.Exit(run(entries, os.Args[1:], c))
}

// run runs the entry of table that args[0] names, with the rest of args as its arguments, and returns
// its exit code. A name with no entry, and an entry that needs the frame when c has none, fail with one
// line and exitUsage.
func run(table map[string]entry, args []string, c *call) int {
	name := ""
	if len(args) > 0 {
		name, c.args = args[0], args[1:]
	}
	e, ok := table[name]
	if !ok {
		return c.die(exitUsage, "the binary has no command '"+name+"'")
	}
	if e.needsFrame && c.frame.project == "" {
		return c.die(exitUsage, name+" needs the frame bin/swarm.sh sets up: run it through bin/swarm.sh")
	}
	return e.run(c)
}

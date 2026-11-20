// Command swarm is the Go port of bin/swarm.sh. No command is ported yet: every run prints that on
// stderr and exits 2.
package main

import (
	"fmt"
	"io"
	"os"
)

// notPorted is the line every run prints on stderr while no command is ported.
const notPorted = "swarm: no command is ported yet"

// exitUsage is the exit code of a run that does nothing: no command is ported yet.
const exitUsage = 2

func main() {
	os.Exit(run(os.Args[1:], os.Stderr))
}

// run runs swarm with args (os.Args without the program name), writes its messages to stderr and
// returns the exit code. No command is ported yet, so it ignores args.
func run(args []string, stderr io.Writer) int {
	// The code already says the run did nothing; a stderr that fails to take the line cannot change it.
	_, _ = fmt.Fprintln(stderr, notPorted)
	return exitUsage
}

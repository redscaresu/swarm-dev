// Package store is the one implementation of iface.Store: the files under .swarm/, the board's
// files and the files bin/swarm.sh hands the binary (the die file and the fields file). It reads and
// writes them itself and runs no program.
package store

import (
	"os"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// fileMode is the mode of a file the store makes: the owner's alone, as mktemp makes them.
const fileMode = 0o600

// Files reads and writes .swarm/, the board's files and the files bin/swarm.sh hands the binary.
type Files struct{}

var _ iface.Store = Files{}

// WriteLine makes path hold line and a newline, and nothing else.
func (Files) WriteLine(path, line string) error {
	return os.WriteFile(path, []byte(line+"\n"), fileMode)
}

// AppendLines adds each line, with a newline, to the end of path, making the file if it is missing.
func (Files) AppendLines(path string, lines []string) error {
	if len(lines) == 0 {
		return nil
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, fileMode)
	if err != nil {
		return err
	}
	_, werr := f.WriteString(strings.Join(lines, "\n") + "\n")
	cerr := f.Close()
	if werr != nil {
		return werr
	}
	return cerr
}

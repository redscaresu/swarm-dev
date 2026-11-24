// Package store is the one implementation of iface.Store: the files under .swarm/, the board's
// files and the files bin/swarm.sh hands the binary (the die file and the fields file), and a file
// bash names in an argument, such as .claude.json. It reads and writes them itself and runs no program.
package store

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// fileMode is the mode of a frame file the store makes: the owner's alone, as mktemp makes them.
const fileMode = 0o600

// appendMode is the mode AppendLine makes a file with, before the umask, as bash's >> makes it.
const appendMode = 0o666

// dirMode is the mode AppendLine makes a folder with, before the umask, as mkdir -p makes it.
const dirMode = 0o777

// Files reads and writes .swarm/, the board's files and the files bin/swarm.sh hands the binary.
type Files struct{}

var _ iface.Store = Files{}

// ReadFile returns all of path's bytes, or the error the read returned.
func (Files) ReadFile(path string) ([]byte, error) {
	return os.ReadFile(path)
}

// Stat returns path's file info, following a symlink. Its error wraps fs.ErrNotExist or
// fs.ErrPermission where the stat failed for that reason, so callers test it with errors.Is.
func (Files) Stat(path string) (fs.FileInfo, error) {
	return os.Stat(path)
}

// Lstat returns path's file info without following a last symlink, so a dangling symlink has one.
// Its error wraps fs.ErrNotExist or fs.ErrPermission as Stat's does.
func (Files) Lstat(path string) (fs.FileInfo, error) {
	return os.Lstat(path)
}

// RealPath returns the physical path `cd <dir> && pwd -P` prints, failing for a missing path or a
// file. As bash's cd does, it first takes dir's . and .. lexically, where the folder before each ..
// must exist; when that path is no folder, it takes dir as written, with each .. physical. Either way
// every symlink is then resolved. It differs from cd in two cases: a folder the caller may not enter,
// whose path it returns where cd fails, and a path that starts with exactly //, which it returns with
// one slash where pwd -P keeps two.
func (Files) RealPath(dir string) (string, error) {
	abs := dir
	if !filepath.IsAbs(dir) {
		wd, err := os.Getwd()
		if err != nil {
			return "", err
		}
		abs = wd + string(filepath.Separator) + dir
	}
	if logical, ok := lexicalPath(abs); ok && isDir(logical) {
		return filepath.EvalSymlinks(logical)
	}
	if !isDir(abs) {
		return "", fmt.Errorf("%s: not a folder", dir)
	}
	return filepath.EvalSymlinks(abs)
}

// lexicalPath takes abs's . and .. as words, not links, as bash's cd does before it changes folder.
// It fails where the path before a .. is not a folder, as cd then does.
func lexicalPath(abs string) (string, bool) {
	sep := string(filepath.Separator)
	kept := []string{}
	for _, part := range strings.Split(abs, sep) {
		switch part {
		case "", ".":
		case "..":
			if !isDir(sep + strings.Join(kept, sep)) {
				return "", false
			}
			if len(kept) > 0 {
				kept = kept[:len(kept)-1]
			}
		default:
			kept = append(kept, part)
		}
	}
	return sep + strings.Join(kept, sep), true
}

// isDir reports whether path, its symlinks followed, is a folder.
func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// AppendLine makes path's parent folders as mkdir -p does, then adds line and a newline to the end
// of path in one O_APPEND write, making the file if it is missing. It returns the error of the step
// that failed. The parent is path up to its last separator, not cleaned, so a .. after a symlink
// makes the folder the open then writes in, as mkdir -p does.
func (Files) AppendLine(path, line string) error {
	if err := os.MkdirAll(rawParent(path), dirMode); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, appendMode)
	if err != nil {
		return err
	}
	_, werr := f.WriteString(line + "\n")
	cerr := f.Close()
	if werr != nil {
		return werr
	}
	return cerr
}

// rawParent is path up to its last separator, with no . or .. taken away: "." for a bare name and
// the root for a name just under it.
func rawParent(path string) string {
	i := strings.LastIndexByte(path, filepath.Separator)
	switch {
	case i < 0:
		return "."
	case i == 0:
		return string(filepath.Separator)
	}
	return path[:i]
}

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

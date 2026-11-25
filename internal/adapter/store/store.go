// Package store is the one implementation of iface.Store: the files under .swarm/, the board's
// files and the files bin/swarm.sh hands the binary (the die file and the fields file), and a file
// bash names in an argument, such as .claude.json. It reads, lists, writes and removes them itself and
// runs no program. It also says whether a pid runs, for a lock's holder.
package store

import (
	"errors"
	"fmt"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// fileMode is the mode of a frame file the store makes: the owner's alone, as mktemp makes them.
const fileMode = 0o600

// appendMode is the mode AppendLine makes a file with, before the umask, as bash's >> makes it.
const appendMode = 0o666

// exclusiveMode is the mode CreateExclusive makes a file with, before the umask, as poll_cache.py's
// lock opens its lock file.
const exclusiveMode = 0o644

// dirMode is the mode AppendLine and MkdirAll make a folder with, before the umask, as mkdir -p and
// Python's os.makedirs make it.
const dirMode = 0o777

// tempPattern names WriteAtomic's temp file as Python's tempfile.mkstemp(suffix=".tmp") does: tmp, a
// random part, then .tmp, the suffix the pane-state readers skip.
const tempPattern = "tmp*.tmp"

// globMeta holds the bytes that make a level of a Glob pattern a pattern rather than a name: the three
// Python's glob takes as magic, and the backslash, which filepath.Match takes as an escape.
const globMeta = `*?[\`

// Files reads, lists, writes and removes .swarm/, the board's files and the files bin/swarm.sh hands
// the binary.
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

// Glob returns the paths under dir that pattern matches, sorted, as Python's
// sorted(glob.glob(os.path.join(glob.escape(dir), pattern))) lists them. dir is taken literally: a
// folder named with [, ], *, ? or \ is that folder, not a pattern. Each path is dir, a separator and
// the names each level matched, joined as os.path.join joins them and never cleaned, so a .. after a
// symlink in dir stays the folder it names. pattern is filepath.Match's syntax, and may name more than
// one level (*/x.jsonl). As in Python, a level of pattern that does not start with a dot matches no
// name that does, and a level with no *, ?, [ or \ is a name, found without listing its folder. No
// match, a missing dir or one that cannot be read gives no paths and no error. The one error is
// filepath.ErrBadPattern: for a malformed level, and for an empty, . or .. level, which no folder lists.
func (Files) Glob(dir, pattern string) ([]string, error) {
	levels := strings.Split(pattern, string(filepath.Separator))
	for _, level := range levels {
		if !wellFormed(level) || level == "" || level == "." || level == ".." {
			return nil, filepath.ErrBadPattern
		}
	}
	paths := []string{dir}
	for _, level := range levels {
		var next []string
		for _, base := range paths {
			next = append(next, globLevel(base, level)...)
		}
		paths = next
	}
	sort.Strings(paths)
	return paths, nil
}

// wellFormed reports whether filepath.Match takes level without filepath.ErrBadPattern. Match stops at
// the first part that fails to match and checks no part after it, so Match(level, "") passes x*[. This
// checks each part on its own: level split at each * outside a [ ] class, as Match's scanChunk splits
// it, a backslash keeping the byte after it.
func wellFormed(level string) bool {
	inClass, start := false, 0
	for i := 0; i < len(level); i++ {
		switch c := level[i]; {
		case c == '\\' && i+1 < len(level):
			i++
		case c == '[':
			inClass = true
		case c == ']':
			inClass = false
		case c == '*' && !inClass:
			if !matchTakes(level[start:i]) {
				return false
			}
			start = i + 1
		}
	}
	return matchTakes(level[start:])
}

// matchTakes reports whether filepath.Match takes part, a level with no * outside a class, without
// filepath.ErrBadPattern: Match checks all of such a part, even once it fails to match.
func matchTakes(part string) bool {
	_, err := filepath.Match(part, "") // loose-match: ok only checks the caller's pattern is well formed
	return err == nil
}

// globLevel returns the paths in folder base that level, one level of a Glob pattern, matches: a name
// that exists, for a level that is a name, or each name in base that level matches, skipping a dot
// name unless level starts with a dot. A base that is no folder, or cannot be read, gives none.
func globLevel(base, level string) []string {
	if !strings.ContainsAny(level, globMeta) {
		path := joinRaw(base, level)
		if _, err := os.Lstat(path); err != nil {
			return nil
		}
		return []string{path}
	}
	list := base
	if list == "" {
		list = "."
	}
	entries, err := os.ReadDir(list)
	if err != nil {
		return nil
	}
	var paths []string
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") && !strings.HasPrefix(level, ".") {
			continue
		}
		if ok, _ := filepath.Match(level, name); ok { // loose-match: ok level is a level of the caller's pattern, checked in Glob
			paths = append(paths, joinRaw(base, name))
		}
	}
	return paths
}

// joinRaw joins base and name as Python's os.path.join does: with one separator, none added after a
// base that ends in one, name alone after an empty base, and nothing cleaned.
func joinRaw(base, name string) string {
	switch {
	case base == "":
		return name
	case strings.HasSuffix(base, string(filepath.Separator)):
		return base + name
	}
	return base + string(filepath.Separator) + name
}

// IsFile reports whether path, its symlinks followed, is a regular file, as Python's os.path.isfile
// does: false for a folder, a missing path or one that cannot be stat'ed. A caller that must tell those
// apart uses Stat, which returns the error.
func (Files) IsFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// MkdirAll makes path and each missing folder above it, as mkdir -p and Python's
// os.makedirs(exist_ok=True) do, 0777 before the umask. A path that is already a folder is no error;
// one that is a file is. It returns the os error, so errors.Is tells fs.ErrPermission apart.
func (Files) MkdirAll(path string) error {
	return os.MkdirAll(path, dirMode)
}

// WriteAtomic makes path hold data and nothing else, so a reader sees the old file or the new one,
// never a part of either. As Python's gh_cache.put does, it writes a temp file (0600, named by
// tempPattern) in path's own folder, which must exist, then renames it over path. When any step
// fails it removes the temp file, leaves path as it was and returns the step's os error, joined with
// the remove's error if that fails too.
func (Files) WriteAtomic(path string, data []byte) (err error) {
	f, err := os.CreateTemp(rawParent(path), tempPattern)
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			if rerr := os.Remove(f.Name()); rerr != nil {
				err = errors.Join(err, rerr)
			}
		}
	}()
	if _, err = f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}

// Remove deletes the file or symlink path, as Python's os.remove does, and never a folder, which
// os.Remove would take when empty. It returns the os error, so errors.Is tells fs.ErrNotExist apart.
func (Files) Remove(path string) error {
	if err := syscall.Unlink(path); err != nil {
		return &fs.PathError{Op: "remove", Path: path, Err: err}
	}
	return nil
}

// CreateExclusive makes path holding data, as poll_cache.py's lock makes a lock file: an open with
// O_CREAT|O_EXCL, 0644 before the umask, then one write. The open fails when path is there in any
// form, a dangling symlink too, with an error wrapping fs.ErrExist, and leaves it as it was. When
// the write or the close fails it removes path again and returns that error, joined with the
// remove's error if that fails too.
func (Files) CreateExclusive(path string, data []byte) (err error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, exclusiveMode)
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			if rerr := os.Remove(path); rerr != nil {
				err = errors.Join(err, rerr)
			}
		}
	}()
	if _, err = f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

// RemoveDir deletes the folder path when it is empty, as Python's os.rmdir does, and never a file
// or a folder that holds anything. It returns the os error, so errors.Is tells fs.ErrNotExist apart.
func (Files) RemoveDir(path string) error {
	if err := syscall.Rmdir(path); err != nil {
		return &fs.PathError{Op: "rmdir", Path: path, Err: err}
	}
	return nil
}

// Alive reports whether process pid runs, as ci_gate.py's alive does: a signal 0 that finds it, or
// is refused because another user owns it. It is false for a pid of 0 or less, which kill would
// take as a process group, and for one past the largest pid_t, which Python's os.kill refuses with
// an OverflowError and Go's syscall would cut down to another pid.
func (Files) Alive(pid int) bool {
	if pid <= 0 || pid > math.MaxInt32 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

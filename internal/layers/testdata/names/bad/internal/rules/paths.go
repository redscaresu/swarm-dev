package rules

import (
	"io/fs"
	"path/filepath"
)

// Find reads the working directory and the file tree. Join reads no file, so it is allowed.
func Find(root string) error {
	_, _ = filepath.Abs(filepath.Join(root, "x"))
	_, _ = filepath.Glob("*.go")
	return filepath.WalkDir(root, func(string, fs.DirEntry, error) error { return nil })
}

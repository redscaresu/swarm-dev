package store

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
)

// If ReadFile drops or changes a byte (a last newline, a NUL, bytes that are not UTF-8), the rule
// that reads .claude.json decides on other text than the file holds: this goes red.
func TestReadFileReturnsEveryByte(t *testing.T) {
	path := filepath.Join(t.TempDir(), "f")
	want := []byte("{\"a\": 1}\n\x00\xff no newline at the end")
	if err := os.WriteFile(path, want, fileMode); err != nil {
		t.Fatal(err)
	}
	got, err := Files{}.ReadFile(path)
	if err != nil || !bytes.Equal(got, want) {
		t.Errorf("ReadFile(%s) = %q, %v; want %q, nil", path, got, err, want)
	}
}

// If ReadFile hides a failed read (a missing file, a folder) behind empty bytes and no error, the
// caller cannot tell "no file" from "an empty file": this goes red.
func TestReadFileReturnsTheReadsError(t *testing.T) {
	dir := t.TempDir()
	for _, c := range []struct {
		name, path string
		is         error // the error the read must wrap, or nil for any error
	}{
		{"a missing file", filepath.Join(dir, "none"), fs.ErrNotExist},
		{"a folder", dir, nil},
	} {
		got, err := Files{}.ReadFile(c.path)
		if err == nil || (c.is != nil && !errors.Is(err, c.is)) {
			t.Errorf("%s: ReadFile(%s) = %q, %v; want an error (wrapping %v)", c.name, c.path, got, err, c.is)
		}
	}
}

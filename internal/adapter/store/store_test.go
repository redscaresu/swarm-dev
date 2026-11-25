package store

import (
	"bytes"
	"context"
	"errors"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// bashTimeout bounds the one bash the RealPath test runs.
const bashTimeout = 30 * time.Second

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

// If ReadFile or Stat of a missing path returns an error that does not wrap fs.ErrNotExist, a caller
// testing errors.Is(err, fs.ErrNotExist) takes "no file" for a read that failed: this goes red.
func TestMissingPathErrorsWrapNotExist(t *testing.T) {
	path := filepath.Join(t.TempDir(), "none")
	if _, err := (Files{}).ReadFile(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("ReadFile(%s) error = %v, want one wrapping fs.ErrNotExist", path, err)
	}
	if _, err := (Files{}).Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("Stat(%s) error = %v, want one wrapping fs.ErrNotExist", path, err)
	}
}

// If Lstat follows the last symlink, as Stat does, a dangling symlink reads as no file: this goes red.
func TestLstatSeesADanglingSymlink(t *testing.T) {
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(filepath.Join(filepath.Dir(link), "gone"), link); err != nil {
		t.Fatal(err)
	}
	if _, err := (Files{}).Stat(link); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("Stat(%s) error = %v, want one wrapping fs.ErrNotExist", link, err)
	}
	info, err := Files{}.Lstat(link)
	if err != nil || info.Mode()&fs.ModeSymlink == 0 {
		t.Errorf("Lstat(%s) = %v, %v; want a symlink's info and no error", link, info, err)
	}
}

// If ReadFile of a file it may not read returns an error that does not wrap fs.ErrPermission, a
// caller cannot tell "not allowed" from other failures: this goes red. Root reads any file, so the
// case is skipped as root.
func TestReadFileOfAnUnreadableFileWrapsPermission(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads a chmod 000 file")
	}
	path := filepath.Join(t.TempDir(), "locked")
	if err := os.WriteFile(path, []byte("x\n"), 0o000); err != nil {
		t.Fatal(err)
	}
	if _, err := (Files{}).ReadFile(path); !errors.Is(err, fs.ErrPermission) {
		t.Errorf("ReadFile(%s) error = %v, want one wrapping fs.ErrPermission", path, err)
	}
}

// If RealPath returns its argument unresolved, or takes a . or .. otherwise than bash's cd does (a
// .. after a missing folder or a file, a .. after a symlink, a logical path that is no folder), a
// caller compares a path against the one bash would print and finds them different: this goes red.
// Each case's want is checked against `cd <path> && pwd -P`, run for all of them in one bash.
func TestRealPathMatchesPwdP(t *testing.T) {
	root := t.TempDir()
	for _, d := range []string{"target/sub", "base", "real"} {
		if err := os.MkdirAll(filepath.Join(root, d), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "file"), nil, fileMode); err != nil {
		t.Fatal(err)
	}
	for link, to := range map[string]string{"base/link": "target/sub", "dang": "gone", "rl": "real"} {
		if err := os.Symlink(filepath.Join(root, to), filepath.Join(root, link)); err != nil {
			t.Fatal(err)
		}
	}
	cases := []struct {
		name, path string
		ok         bool // whether cd succeeds, pinned so a bash that fails every case cannot pass
	}{
		{"a symlink to a folder", "base/link", true},
		{"a .. after a symlink, taken lexically", "base/link/..", true},
		{"a .. after a symlink, its lexical path no folder", "base/link/../sub", true},
		{"a .. after a symlink, back through another", "rl/../real", true},
		{"a .. after a missing folder", "missing/..", false},
		{"a .. after a file", "file/..", false},
		{"a .. after a dangling symlink", "dang/..", false},
		{"a missing path", "missing", false},
	}
	args := []string{"-c", `for d in "$@"; do (cd "$d" 2>/dev/null && pwd -P) || echo "cd failed"; done`, "bash"}
	for _, c := range cases {
		args = append(args, root+"/"+c.path)
	}
	ctx, cancel := context.WithTimeout(context.Background(), bashTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "bash", args...).Output()
	if err != nil {
		t.Fatalf("bash cd && pwd -P: %v", err)
	}
	lines := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	if len(lines) != len(cases) {
		t.Fatalf("bash printed %d lines for %d cases: %q", len(lines), len(cases), out)
	}
	for i, c := range cases {
		path := root + "/" + c.path // not filepath.Join, which would take the .. away before bash sees it
		if bashOK := lines[i] != "cd failed"; bashOK != c.ok {
			t.Fatalf("%s: bash cd %s printed %q, want it to succeed: %v", c.name, path, lines[i], c.ok)
		}
		got, err := Files{}.RealPath(path)
		switch {
		case !c.ok && err == nil:
			t.Errorf("%s: RealPath(%s) = %q, nil; want an error, as cd fails", c.name, path, got)
		case c.ok && (err != nil || got != lines[i]):
			t.Errorf("%s: RealPath(%s) = %q, %v; want %q, nil", c.name, path, got, err, lines[i])
		}
	}
	if want := filepath.Join(root, "base/link"); lines[0] == want {
		t.Fatalf("pwd -P printed the link itself, %s: the test cannot tell resolved from unresolved", want)
	}
}

// If RealPath accepts a regular file, as cd does not, a caller takes a file for a project folder:
// this goes red.
func TestRealPathOfAFileFails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(path, nil, fileMode); err != nil {
		t.Fatal(err)
	}
	if got, err := (Files{}).RealPath(path); err == nil {
		t.Errorf("RealPath(%s) = %q, nil; want an error for a file", path, got)
	}
}

// If AppendLine does not make the missing folder, the first event in a fresh project is lost; if it
// writes more or fewer lines than it is called with, or makes the file with other than bash's >> mode,
// the log differs from the one bash writes: this goes red.
func TestAppendLineMakesTheFolderAndAddsOneLineEachCall(t *testing.T) {
	path := filepath.Join(t.TempDir(), "p", ".swarm", "events.tsv")
	for _, line := range []string{"one\ta", "two\tb"} {
		if err := (Files{}).AppendLine(path, line); err != nil {
			t.Fatalf("AppendLine(%s, %q) = %v, want nil", path, line, err)
		}
	}
	got, err := os.ReadFile(path)
	if want := "one\ta\ntwo\tb\n"; err != nil || string(got) != want {
		t.Errorf("%s holds %q, %v; want %q", path, got, err, want)
	}
	mask := syscall.Umask(0)
	syscall.Umask(mask)
	info, err := os.Stat(path)
	// 0666 is written out, not appendMode, so a change to the constant goes red here.
	if want := fs.FileMode(0o666 &^ mask); err != nil || info.Mode().Perm() != want {
		t.Errorf("%s mode = %v, %v; want %v (0666 less the umask %03o)", path, info.Mode().Perm(), err, want, mask)
	}
}

// If AppendLine makes a parent with its .. taken lexically, a path with a .. after a symlink gets a
// folder where mkdir -p makes none, and the open, which takes the .. physically, finds no folder:
// this goes red. base/link points at target/sub, so mkdir -p base/link/../new makes target/new.
func TestAppendLineMakesTheParentMkdirPMakes(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "target", "sub"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(root, "base"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(root, "target", "sub"), filepath.Join(root, "base", "link")); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "base", "link") + "/../new/events.tsv"
	if err := (Files{}).AppendLine(path, "x"); err != nil {
		t.Fatalf("AppendLine(%s) = %v, want nil", path, err)
	}
	want := filepath.Join(root, "target", "new", "events.tsv")
	if got, err := os.ReadFile(want); err != nil || string(got) != "x\n" {
		t.Errorf("%s holds %q, %v; want %q", want, got, err, "x\n")
	}
	if _, err := os.Lstat(filepath.Join(root, "base", "new")); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("base/new: Lstat error = %v; want none made, as mkdir -p makes none", err)
	}
}

// If AppendLine hides a folder it could not make behind a nil error, the caller believes a line was
// logged that never was: this goes red. The file in the folder's place must be left as it was.
func TestAppendLineFailsWhenTheFolderCannotBeMade(t *testing.T) {
	blocker := filepath.Join(t.TempDir(), "q", ".swarm")
	if err := os.MkdirAll(filepath.Dir(blocker), 0o700); err != nil {
		t.Fatal(err)
	}
	want := []byte("a regular file\n")
	if err := os.WriteFile(blocker, want, fileMode); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(blocker, "events.tsv")
	if err := (Files{}).AppendLine(path, "lost"); err == nil {
		t.Errorf("AppendLine(%s) = nil, want an error: %s is a file", path, blocker)
	}
	if got, err := os.ReadFile(blocker); err != nil || !bytes.Equal(got, want) {
		t.Errorf("%s holds %q, %v after AppendLine; want %q", blocker, got, err, want)
	}
}

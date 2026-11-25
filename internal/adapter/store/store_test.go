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

// pythonTimeout bounds the one python3 the Glob test runs.
const pythonTimeout = 30 * time.Second

// If Glob reads its folder as a pattern (a folder named with [, ], *, ?, or \, which Match takes as an
// escape), or matches a dot name its pattern level does not ask for, a caller lists another folder's
// files, or none, where Python's glob.glob(os.path.join(glob.escape(dir), pattern)) lists these: this
// goes red. So it does if Glob cleans a .. after a symlink in dir away, naming a file other than the
// one it found. Each case is pinned and checked against that Python, run for all of them in one
// python3. The decoy folder is the one the literal folder's name matches when read as a pattern.
func TestGlobMatchesPythonsEscapedGlob(t *testing.T) {
	root := t.TempDir()
	literal, decoy := `a[b]*?c\d`, "abXYcd"
	for _, f := range []string{
		literal + "/x-1.json", literal + "/x-2.json", literal + "/y.txt", decoy + "/x-9.json",
		".cache/x.json", ".cache/.h.json", ".cache/p/f.jsonl", ".cache/p-b/f.jsonl", ".cache/.q/f.jsonl",
		"target/a.json", "target/sub/s.json", "base/b.json",
	} {
		path := filepath.Join(root, f)
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, fileMode); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(root, "target", "sub"), filepath.Join(root, "base", "link")); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name, dir, pattern string
		want               []string // under root, pinned so a python3 that prints nothing cannot pass
	}{
		{"a folder named with [, ], *, ? and \\", literal, "x-*.json", []string{literal + "/x-1.json", literal + "/x-2.json"}},
		{"a * level skips dot names, in a dot folder", ".cache", "*.json", []string{".cache/x.json"}},
		{"a dot level matches dot names", ".cache", ".*.json", []string{".cache/.h.json"}},
		// p-b/ sorts before p/, though the folder p sorts before p-b
		{"a * level above another skips dot folders, sorted as paths", ".cache", "*/f.jsonl",
			[]string{".cache/p-b/f.jsonl", ".cache/p/f.jsonl"}},
		{"a level that is a name", ".cache", "p/f.jsonl", []string{".cache/p/f.jsonl"}},
		// link/.. is target, physically; cleaned, it would read base/a.json, which is not there
		{"a .. after a symlink in dir, kept as written", "base/link/..", "*.json", []string{"base/link/../a.json"}},
		{"a missing folder", "none", "*", nil},
	}
	script := `import glob, os, sys
for d, p in zip(sys.argv[1::2], sys.argv[2::2]):
    print("\0".join(sorted(glob.glob(os.path.join(glob.escape(d), p)))))`
	args := []string{"-c", script}
	for _, c := range cases {
		args = append(args, root+"/"+c.dir, c.pattern) // not filepath.Join, which would clean a ..
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "python3", args...).Output()
	if err != nil {
		t.Fatalf("python3 glob.glob: %v", err)
	}
	lines := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	if len(lines) != len(cases) {
		t.Fatalf("python3 printed %d lines for %d cases: %q", len(lines), len(cases), out)
	}
	for i, c := range cases {
		want := []string{}
		for _, w := range c.want {
			want = append(want, root+"/"+w)
		}
		if py := strings.Join(want, "\x00"); lines[i] != py {
			t.Fatalf("%s: python3 listed %q, want %q", c.name, lines[i], py)
		}
		got, err := Files{}.Glob(root+"/"+c.dir, c.pattern)
		if err != nil || strings.Join(got, "\x00") != lines[i] {
			t.Errorf("%s: Glob(%s, %s) = %q, %v; want %q, nil", c.name, c.dir, c.pattern, got, err, want)
		}
	}
}

// If Glob changes a byte of its folder's name that is not UTF-8 (to U+FFFD, as a range over runes
// does), it lists another folder or none: this goes red. It runs on a file system that takes such a
// name: macOS's APFS refuses it, and Linux's CI runs it.
func TestGlobKeepsAFolderNamesBytes(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "x\xff[")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Skipf("this file system refuses a folder name that is not UTF-8: %v", err)
	}
	file := filepath.Join(dir, "a.json")
	if err := os.WriteFile(file, nil, fileMode); err != nil {
		t.Fatal(err)
	}
	if got, err := (Files{}).Glob(dir, "*.json"); err != nil || strings.Join(got, ",") != file {
		t.Errorf("Glob(%q, *.json) = %q, %v; want [%q], nil", dir, got, err, file)
	}
}

// If Glob swallows a malformed pattern as no match, a caller's typo lists nothing and reads as an empty
// folder: this goes red. So it does if Glob checks a level only up to its first part that fails to
// match, as filepath.Match does, or takes a pattern with an empty, . or .. level, which no folder lists.
func TestGlobOfABadPatternFails(t *testing.T) {
	dir := filepath.Join(t.TempDir(), ".cache")
	file := filepath.Join(dir, "p", "f.jsonl")
	if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, nil, fileMode); err != nil {
		t.Fatal(err)
	}
	// p*[ and p*\ are malformed only past a *, where filepath.Match(level, "") stops checking.
	for _, pattern := range []string{
		"[", "p*[", "p*\\", "*/x*[", "p/./*.jsonl", "p/../p/*.jsonl", "p//*.jsonl", "./p/*.jsonl", "p/",
	} {
		if got, err := (Files{}).Glob(dir, pattern); !errors.Is(err, filepath.ErrBadPattern) {
			t.Errorf("Glob(dir, %q) = %q, %v; want filepath.ErrBadPattern", pattern, got, err)
		}
	}
	// A * inside a class splits no part: a check that split there would refuse this good pattern.
	if got, err := (Files{}).Glob(dir, "p/[*f]*.jsonl"); err != nil || strings.Join(got, ",") != file {
		t.Errorf("Glob(dir, %q) = %q, %v; want [%q], nil", "p/[*f]*.jsonl", got, err, file)
	}
}

// If IsFile takes a folder, a missing path or a dangling symlink for a file, or misses a file behind a
// symlink, a caller reads a story that is not there or skips one that is: this goes red.
func TestIsFileIsTrueForARegularFileAlone(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "f")
	if err := os.WriteFile(file, nil, fileMode); err != nil {
		t.Fatal(err)
	}
	for link, to := range map[string]string{"to-file": file, "to-root": root, "dang": filepath.Join(root, "gone")} {
		if err := os.Symlink(to, filepath.Join(root, link)); err != nil {
			t.Fatal(err)
		}
	}
	for path, want := range map[string]bool{
		"f": true, "to-file": true, ".": false, "to-root": false, "dang": false, "gone": false,
	} {
		if got := (Files{}).IsFile(filepath.Join(root, path)); got != want {
			t.Errorf("IsFile(%s) = %v, want %v", path, got, want)
		}
	}
}

// If MkdirAll stops short of the last folder, fails on one already there, or hides a file in the way
// behind a nil error, a caller writes into a folder that is not there: this goes red.
func TestMkdirAllMakesEachFolderAndFailsOnAFile(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "a", "b", "c")
	for i := 0; i < 2; i++ { // the second call finds every folder already made
		if err := (Files{}).MkdirAll(path); err != nil {
			t.Fatalf("MkdirAll(%s) call %d = %v, want nil", path, i+1, err)
		}
	}
	if info, err := os.Stat(path); err != nil || !info.IsDir() {
		t.Errorf("%s after MkdirAll: %v, %v; want a folder", path, info, err)
	}
	blocker := filepath.Join(root, "file")
	if err := os.WriteFile(blocker, []byte("kept"), fileMode); err != nil {
		t.Fatal(err)
	}
	if err := (Files{}).MkdirAll(filepath.Join(blocker, "sub")); err == nil {
		t.Errorf("MkdirAll(%s/sub) = nil, want an error: %s is a file", blocker, blocker)
	}
	if got, err := os.ReadFile(blocker); err != nil || string(got) != "kept" {
		t.Errorf("%s holds %q, %v after MkdirAll; want %q", blocker, got, err, "kept")
	}
}

// dirNames returns the names in dir, sorted, failing the test when it cannot read it.
func dirNames(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	names := []string{}
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return names
}

// If WriteAtomic leaves its temp file beside the target, keeps the old bytes, or makes the file
// readable by others where Python's mkstemp makes it 0600, the next reader sees a stray .tmp or stale
// content: this goes red.
func TestWriteAtomicReplacesTheFileAndLeavesNoTempFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "pulls.json")
	if err := os.WriteFile(path, []byte("old content, longer than the new"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := (Files{}).WriteAtomic(path, []byte("new")); err != nil {
		t.Fatalf("WriteAtomic(%s) = %v, want nil", path, err)
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "new" {
		t.Errorf("%s holds %q, %v; want %q", path, got, err, "new")
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != fileMode {
		t.Errorf("%s mode: %v, %v; want %v", path, info.Mode(), err, os.FileMode(fileMode))
	}
	if got := dirNames(t, dir); strings.Join(got, ",") != "pulls.json" {
		t.Errorf("%s holds %q after WriteAtomic; want only pulls.json", dir, got)
	}
}

// If WriteAtomic leaves its temp file behind when the rename fails, or loses the error, the folder
// fills with .tmp files and the caller believes the write landed: this goes red. The target here is a
// folder, which no file can be renamed over, and what it held must be left as it was.
func TestWriteAtomicLeavesNoTempFileWhenTheWriteFails(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "pulls.json")
	if err := os.MkdirAll(target, 0o700); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(target, "old")
	if err := os.WriteFile(old, []byte("old"), fileMode); err != nil {
		t.Fatal(err)
	}
	if err := (Files{}).WriteAtomic(target, []byte("new")); err == nil {
		t.Errorf("WriteAtomic(%s) = nil, want an error: it is a folder", target)
	}
	if got := dirNames(t, dir); strings.Join(got, ",") != "pulls.json" {
		t.Errorf("%s holds %q after a failed WriteAtomic; want only pulls.json, no temp file", dir, got)
	}
	if got, err := os.ReadFile(old); err != nil || string(got) != "old" {
		t.Errorf("%s holds %q, %v after a failed WriteAtomic; want %q", old, got, err, "old")
	}
	missing := filepath.Join(dir, "none", "pulls.json")
	if err := (Files{}).WriteAtomic(missing, []byte("new")); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("WriteAtomic(%s) = %v, want an error wrapping fs.ErrNotExist: its folder is missing", missing, err)
	}
}

// If Remove takes an empty folder, as os.Remove does and Python's os.remove does not, follows a
// symlink to its target, or drops the error for a missing file, a caller deletes what it never named
// or takes a failed delete for a done one: this goes red.
func TestRemoveDeletesAFileOrLinkAndNeverAFolder(t *testing.T) {
	root := t.TempDir()
	file, link, folder := filepath.Join(root, "f"), filepath.Join(root, "l"), filepath.Join(root, "d")
	if err := os.WriteFile(file, nil, fileMode); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(file, link); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(folder, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := (Files{}).Remove(link); err != nil {
		t.Errorf("Remove(%s) = %v, want nil", link, err)
	}
	if got := dirNames(t, root); strings.Join(got, ",") != "d,f" {
		t.Errorf("%s holds %q after removing the link; want d,f", root, got)
	}
	if err := (Files{}).Remove(file); err != nil {
		t.Errorf("Remove(%s) = %v, want nil", file, err)
	}
	if err := (Files{}).Remove(folder); err == nil {
		t.Errorf("Remove(%s) = nil, want an error: it is a folder", folder)
	}
	if got := dirNames(t, root); strings.Join(got, ",") != "d" {
		t.Errorf("%s holds %q; want only the folder d", root, got)
	}
	if err := (Files{}).Remove(file); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("Remove(%s) of a removed file = %v, want an error wrapping fs.ErrNotExist", file, err)
	}
}

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/git"
	"github.com/redscaresu/swarm-dev/internal/iface"
)

// droppedTestBound bounds each git call that builds a test's repository.
const droppedTestBound = 30 * time.Second

// droppedTestRepo is a repository on main whose branch pr merges main and drops "three", a line main
// added to f. It gives the folder and the merge. git runs with no user or system config, and with no
// variable that points it at another repository, for the test's calls, the entry's and main()'s.
func droppedTestRepo(t *testing.T) (string, string) {
	t.Helper()
	for _, k := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT"} {
		t.Setenv(k, "") // puts the old value back when the test ends
		if err := os.Unsetenv(k); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	for _, who := range []string{"AUTHOR", "COMMITTER"} {
		t.Setenv("GIT_"+who+"_NAME", "dropped test")
		t.Setenv("GIT_"+who+"_EMAIL", "dropped@test.invalid")
	}
	dir := t.TempDir()
	run := func(args ...string) string {
		t.Helper()
		got, err := git.Repo{}.Run(iface.GitCall{Dir: dir, Bound: droppedTestBound, Args: args})
		if err != nil || got.TimedOut || got.Code != 0 {
			t.Fatalf("git %q: %v %+v", args, err, got)
		}
		return strings.TrimSpace(got.Stdout)
	}
	commit := func(file, text string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, file), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		run("add", "-A")
		run("commit", "-q", "-m", file)
	}
	run("init", "-q", "-b", "main")
	commit("f", "one\ntwo\n")
	run("checkout", "-q", "-b", "pr")
	commit("g", "pr\n")
	run("checkout", "-q", "main")
	commit("f", "one\ntwo\nthree\n")
	run("checkout", "-q", "pr")
	run("merge", "-q", "--no-ff", "--no-commit", "main")
	commit("f", "one\ntwo\n") // the resolution drops main's "three"
	return dir, run("rev-parse", "HEAD")
}

// droppedCall is a call of the entry with args, the frame bin/swarm.sh hands over and buffers for its
// streams.
func droppedCall(args ...string) (*call, *bytes.Buffer, *bytes.Buffer) {
	var stdout, stderr bytes.Buffer
	c := &call{args: args, stdin: strings.NewReader(""), stdout: &stdout, stderr: &stderr,
		frame: readFrame(handoff("", "")), store: &recordingStore{}}
	return c, &stdout, &stderr
}

// droppedPanics is an iface.Repo whose every call panics, with a message of two lines.
type droppedPanics struct{}

func (droppedPanics) Run(iface.GitCall) (iface.GitResult, error) { panic("git exploded\nmid-read") }

// droppedBadPath is the adapter, with the remerge diff of every merge replaced by one whose --- path
// holds an octal escape droppedUnquote cannot read (\9), as Python's unquote raised on.
type droppedBadPath struct{}

func (droppedBadPath) Run(call iface.GitCall) (iface.GitResult, error) {
	got, err := git.Repo{}.Run(call)
	if slices.Contains(call.Args, "--remerge-diff") {
		got.Stdout = "diff --git a/f b/f\n--- \"a/\\9\"\n+++ b/f\n@@ -1 +1 @@\n-one\n+two\n"
	}
	return got, err
}

// If the entry stops recovering a panic, Go exits 2 with a stack trace, which dropped_lines would read
// as the check's stop. If it exits other than 1, prints on stdout, or leaves a line break in the
// panic's text, the stderr line differs. Each goes red.
func TestDroppedLinesPanic(t *testing.T) {
	c, stdout, stderr := droppedCall(t.TempDir(), "main", "pr")
	code := droppedLines(c, droppedPanics{})
	// Written out here, not built from dropped.go's text, so a change there goes red.
	want := "swarm: _dropped-lines: the check panicked: git exploded mid-read\n"
	if code != 1 || stdout.String() != "" || stderr.String() != want {
		t.Errorf("_dropped-lines over a check that panics: code %d, stdout %q, stderr %q; want 1, nothing, %q",
			code, stdout.String(), stderr.String(), want)
	}
}

// merge.Dropped returns an error where the Python raised, here unquote's on a diff path it cannot
// read. If the entry prints it as a stop (exit 2), passes the code through as 0, or writes more than
// one line, this goes red.
func TestDroppedLinesUnquoteError(t *testing.T) {
	dir, m := droppedTestRepo(t)
	c, stdout, stderr := droppedCall(dir, "main", m)
	code := droppedLines(c, droppedBadPath{})
	const head = "swarm: _dropped-lines: cannot unquote the diff header's path \"\\\"a/\\\\9\\\"\": \\9 is not an octal byte: "
	if code != 1 || stdout.String() != "" || !strings.HasPrefix(stderr.String(), head) ||
		strings.Count(stderr.String(), "\n") != 1 || !strings.HasSuffix(stderr.String(), "\n") {
		t.Errorf("_dropped-lines over unquote's error: code %d, stdout %q, stderr %q; want 1, nothing, one line starting %q",
			code, stdout.String(), stderr.String(), head)
	}
}

// main() with the real table and adapter: the check's lines on stdout and its code, its usage stop,
// and the frame refused. If the entry drops a line, an argument or the code, or loses needsFrame or
// its registration, a row goes red.
func TestDroppedLinesThroughMain(t *testing.T) {
	dir, m := droppedTestRepo(t)
	frame := []string{"SWARMDEV_PROJECT=/proj"}
	usage := "usage: swarm.sh _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...]\n"
	for _, c := range []struct {
		name           string
		env            []string
		args           []string
		code           int
		stdout, stderr string
	}{
		{"a dropped line", frame, []string{dir, "main", m}, 1, m[:7] + " f: three\n", ""},
		{"another merge's SHA given: nothing scanned", frame, []string{dir, "main", m, strings.Repeat("0", 40)}, 0, "", ""},
		{"two arguments: the usage stop", frame, []string{dir, "main"}, 2, usage, ""},
		{"no frame", nil, []string{dir, "main", m}, exitUsage, "",
			"swarm: _dropped-lines needs the frame bin/swarm.sh sets up: run it through bin/swarm.sh\n"},
	} {
		code, stdout, stderr := runMain(t, c.env, "", append([]string{"_dropped-lines"}, c.args...)...)
		if code != c.code || stdout != c.stdout || stderr != c.stderr {
			t.Errorf("main() _dropped-lines, %s: code %d, stdout %q, stderr %q; want %d, %q, %q",
				c.name, code, stdout, stderr, c.code, c.stdout, c.stderr)
		}
	}
}

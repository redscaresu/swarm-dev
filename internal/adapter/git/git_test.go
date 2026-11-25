package git

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// stubGit puts a git on PATH that runs script under sh, and gives the folder it is in.
func stubGit(t *testing.T, script string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "git"), []byte("#!/bin/sh\n"+script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

// readPID reads the process id the stub wrote to path.
func readPID(t *testing.T, path string) int {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		t.Fatal(err)
	}
	return pid
}

// If Run dropped -C, the args, the extra environment or the closed stdin, or gave stdout and stderr
// in place of each other, the stub's output here would differ.
func TestRunPassesCall(t *testing.T) {
	stubGit(t, `printf 'args:'; printf ' [%s]' "$@"; printf '\n'
printf 'X=%s Y=%s\n' "$X" "$Y"
if IFS= read -r line; then printf 'stdin: %s\n' "$line"; else echo 'stdin: none'; fi
printf 'to stderr\r\n' >&2
exit 3
`)
	t.Setenv("Y", "old")
	got, err := Repo{}.Run(iface.GitCall{Dir: "/some dir", Env: []string{"X=1", "Y=new"}, Bound: 10 * time.Second, Args: []string{"fetch", "-q", "a b"}})
	if err != nil {
		t.Fatal(err)
	}
	want := iface.GitResult{
		Code:   3,
		Stdout: "args: [-C] [/some dir] [fetch] [-q] [a b]\nX=1 Y=new\nstdin: none\n",
		Stderr: "to stderr\r\n",
	}
	if got != want {
		t.Errorf("Run = %#v\nwant %#v", got, want)
	}
}

// If Run gave Go's own ExitCode, a git a signal killed would give -1, not minus the signal, and
// report's "exit N" would differ from report.py's.
func TestRunSignalCode(t *testing.T) {
	stubGit(t, "kill -TERM $$\n")
	got, err := Repo{}.Run(iface.GitCall{Dir: ".", Bound: 10 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if got.Code != -int(syscall.SIGTERM) || got.TimedOut {
		t.Errorf("Run of a git killed by SIGTERM = %#v, want Code %d and not TimedOut", got, -int(syscall.SIGTERM))
	}
}

// If Run dropped the bound's kill, git would sleep out its 30 s; if it read on past the bound, the
// child git leaves holding its stdout would keep Run waiting the same 30 s. Either way Run returns
// late. A Code of minus SIGKILL shows git itself was killed, and Run has reaped it.
func TestRunKillsAtBound(t *testing.T) {
	dir := stubGit(t, `sleep 30 & echo $! > "$(dirname "$0")/child"
exec sleep 30
`)
	child := filepath.Join(dir, "child")
	t.Cleanup(func() {
		if _, err := os.Stat(child); err == nil {
			_ = syscall.Kill(readPID(t, child), syscall.SIGTERM)
		}
	})
	const bound = 5 * time.Second // long enough for a loaded machine to start sh and its child
	start := time.Now()
	got, err := Repo{}.Run(iface.GitCall{Dir: ".", Bound: bound})
	took := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}
	if !got.TimedOut || got.Code != -int(syscall.SIGKILL) {
		t.Errorf("Run past the bound = %#v, want TimedOut and Code %d", got, -int(syscall.SIGKILL))
	}
	if limit := bound + 3*time.Second; took > limit {
		t.Errorf("Run took %v, want at most %v: the bound and slack", took, limit)
	}
	if _, err := os.Stat(child); err != nil {
		t.Errorf("the stub's child that holds stdout never started within %v, so the test did not check it: %v", bound, err)
	}
}

// If Run let a bound of zero through, the context would end before git started, and the caller
// would get "context deadline exceeded", which does not say the bound was wrong.
func TestRunRefusesNoBound(t *testing.T) {
	stubGit(t, "exit 0\n")
	if _, err := (Repo{}).Run(iface.GitCall{Dir: "."}); !errors.Is(err, errBound) {
		t.Errorf("Run with no bound gave %v, want %v", err, errBound)
	}
}

// If Run hid a git it could not start behind a result, its caller could not tell it from a git that
// ran and failed.
func TestRunNoGit(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if _, err := (Repo{}).Run(iface.GitCall{Dir: ".", Bound: time.Second}); err == nil {
		t.Error("Run with no git on PATH gave no error")
	}
}

package gh

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// stubPath is the PATH a stub gh runs under: the stub's folder first, then the system's, for cat.
const stubPath = ":/usr/bin:/bin"

// killBound is how soon Run must return once its context ends, for a gh that would sleep for
// sleepSeconds: well under it, so a return in time means gh was killed.
const (
	killBound    = 10 * time.Second
	sleepSeconds = "30"
	ctxEnds      = 300 * time.Millisecond
	startBound   = 20 * time.Second // how long a stub may take to start, on a slow machine
	pollEvery    = 50 * time.Millisecond
)

// stub puts a gh that runs script with /bin/sh first on PATH.
func stub(t *testing.T, script string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\n"+script+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+stubPath)
}

// sleeper puts a gh first on PATH that execs sleep, so the process Run starts is the one that
// sleeps and nothing else holds its output. A symlink named gh will not do: a multi-call sleep, such
// as uutils' on Linux, refuses to run under another name.
func sleeper(t *testing.T) {
	t.Helper()
	stub(t, "exec sleep "+sleepSeconds)
}

// want is what a test expects of a GhResult; noStart says only whether NoStart is set.
type want struct {
	stdout, stderr string
	exit, signal   int
	noStart        bool
	cutShort       bool
}

func check(t *testing.T, got iface.GhResult, w want) {
	t.Helper()
	if !bytes.Equal(got.Stdout, []byte(w.stdout)) || !bytes.Equal(got.Stderr, []byte(w.stderr)) {
		t.Errorf("stdout, stderr = %q, %q; want %q, %q", got.Stdout, got.Stderr, w.stdout, w.stderr)
	}
	if got.Exit != w.exit || got.Signal != w.signal || (got.NoStart != nil) != w.noStart || got.CutShort != w.cutShort {
		t.Errorf("exit %d, signal %d, no start %v, cut short %v; want exit %d, signal %d, no start %v, cut short %v",
			got.Exit, got.Signal, got.NoStart, got.CutShort, w.exit, w.signal, w.noStart, w.cutShort)
	}
}

// If Run hands gh this process's stdin, as Python's stdin=subprocess.DEVNULL never does, a gh that
// reads stdin takes the caller's input, or blocks on a terminal: this goes red.
func TestRunClosesStdin(t *testing.T) {
	stub(t, "exec cat")
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.WriteString("the caller's stdin\n"); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	old := os.Stdin
	os.Stdin = r
	t.Cleanup(func() { os.Stdin = old; _ = r.Close() })
	check(t, Host{}.Run(context.Background()), want{})
}

// If Run decodes, trims or translates gh's output (a NUL, \r\n, bytes that are not UTF-8), the rules
// read other bytes than gh wrote: this goes red.
func TestRunKeepsEveryByte(t *testing.T) {
	stub(t, `printf 'out\377\r\n\000end'; printf 'err \376\n' >&2`)
	check(t, Host{}.Run(context.Background(), "api", "x"), want{stdout: "out\xff\r\n\x00end", stderr: "err \xfe\n"})
}

// If Run loses gh's exit code, or takes a non-zero exit for a failed start, ci_gate's "exit 3" is
// wrong: this goes red.
func TestRunGivesTheExitCode(t *testing.T) {
	stub(t, `printf 'bad\n' >&2; exit 3`)
	check(t, Host{}.Run(context.Background()), want{stderr: "bad\n", exit: 3})
}

// If Run reports a gh that a signal killed as an exit code, ci_gate's "exit -15" is lost: this goes
// red.
func TestRunGivesTheSignal(t *testing.T) {
	stub(t, `printf 'partial'; kill -TERM $$`)
	check(t, Host{}.Run(context.Background()), want{stdout: "partial", exit: -1, signal: int(syscall.SIGTERM)})
}

// If Run takes a gh it could not find for an exit code or a signal, a caller cannot tell "no gh"
// from gh's own failure: this goes red.
func TestRunSaysGhCouldNotStart(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	got := Host{}.Run(context.Background(), "api", "x")
	check(t, got, want{exit: -1, noStart: true})
	if !errors.Is(got.NoStart, exec.ErrNotFound) {
		t.Errorf("NoStart = %v, want one wrapping exec.ErrNotFound", got.NoStart)
	}
}

// If Run lets gh outlive its context's deadline, or reports the kill as a signal, report's bound and
// queued's stop do not hold: this goes red.
func TestRunKillsGhAtTheDeadline(t *testing.T) {
	sleeper(t)
	ctx, cancel := context.WithTimeout(context.Background(), ctxEnds)
	defer cancel()
	start := time.Now()
	got := Host{}.Run(ctx)
	if took := time.Since(start); took > killBound {
		t.Errorf("Run took %s for a gh that sleeps %s s past a %s deadline; want under %s", took, sleepSeconds, ctxEnds, killBound)
	}
	check(t, got, want{exit: -1, cutShort: true})
}

// If Run ignores a cancel, queued's stop leaves gh running: this goes red.
func TestRunKillsGhOnCancel(t *testing.T) {
	sleeper(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stop := time.AfterFunc(ctxEnds, cancel)
	defer stop.Stop()
	start := time.Now()
	got := Host{}.Run(ctx)
	if took := time.Since(start); took > killBound {
		t.Errorf("Run took %s for a gh that sleeps %s s, cancelled after %s; want under %s", took, sleepSeconds, ctxEnds, killBound)
	}
	check(t, got, want{exit: -1, cutShort: true})
}

// Python's subprocess.run reads gh's output to its end. If Run stops at gh's exit, or a short wait
// after it, it hands on output that a process gh started was still writing, cut short but as a
// success: this goes red.
func TestRunReadsOutputToItsEnd(t *testing.T) {
	stub(t, `(sleep 1; printf late) & printf early`)
	check(t, Host{}.Run(context.Background()), want{stdout: "earlylate"})
}

// A gh shim killed where its watcher cannot run (codex's sandbox) leaves the real gh holding the
// output. If Run waits for that output's end after its context ends, report's bound and queued's
// stop do not hold: this goes red.
func TestRunStopsReadingWhenItsContextEnds(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "child")
	stub(t, "sleep "+sleepSeconds+" & echo $! > '"+pidFile+"'; exec sleep "+sleepSeconds)
	t.Cleanup(func() { // the child holding the output, which Run leaves alone, as Python does
		if b, err := os.ReadFile(pidFile); err == nil {
			if pid, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil {
				_ = syscall.Kill(pid, syscall.SIGKILL)
			}
		}
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	got := make(chan iface.GhResult, 1)
	go func() { got <- Host{}.Run(ctx) }()
	for waited := time.Duration(0); waited < startBound; waited += pollEvery {
		if _, err := os.Stat(pidFile); err == nil {
			break
		}
		time.Sleep(pollEvery)
	}
	cancel()
	select {
	case run := <-got:
		check(t, run, want{exit: -1, cutShort: true})
	case <-time.After(killBound):
		t.Errorf("Run still reading %s after its context was cancelled, with gh killed and its child holding the output", killBound)
	}
}

// If Run starts gh under a context already cancelled, a stopped run makes one more call: this goes
// red.
func TestRunStartsNothingOnACancelledContext(t *testing.T) {
	mark := filepath.Join(t.TempDir(), "ran")
	stub(t, ": > '"+mark+"'")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	check(t, Host{}.Run(ctx), want{exit: -1, cutShort: true})
	if _, err := os.Stat(mark); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the stub ran under a cancelled context (stat %s: %v)", mark, err)
	}
}

// Package gh is the one implementation of iface.CodeHost. It runs the gh program found on PATH, so
// the tests' stub gh and the agents' gh shim keep working.
package gh

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
	"syscall"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// ghProgram is the program Run starts, looked up on PATH when Run is called.
const ghProgram = "gh"

// Host reads and changes the code host through gh.
type Host struct{}

var _ iface.CodeHost = Host{}

// Run runs gh from PATH with args, with stdin on /dev/null, as Python's stdin=subprocess.DEVNULL has
// it, and every variable of this process's environment. It reads stdout and stderr to their end, as
// Python's subprocess.run does, so output a process gh started writes after gh ends is kept. When ctx
// ends first, gh gets SIGKILL, as a Python subprocess.run timeout or a signal handler's exception
// sends it, Run stops reading at once, even where a process gh started still holds the output, and
// the result is cut short.
func (Host) Run(ctx context.Context, args ...string) iface.GhResult {
	outR, outW, err := os.Pipe()
	if err != nil {
		return iface.GhResult{Exit: -1, NoStart: err}
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		closeAll(outR, outW)
		return iface.GhResult{Exit: -1, NoStart: err}
	}
	cmd := exec.CommandContext(ctx, ghProgram, args...) // no-timeout: ctx is the caller's bound, as iface.CodeHost's Run says
	// Files, not buffers, so Wait returns when gh ends and the reads below are Run's own to stop.
	cmd.Stdout, cmd.Stderr = outW, errW
	err = cmd.Start()
	closeAll(outW, errW) // gh has its own copies: the reads end once gh and what it started close theirs
	var stdout, stderr bytes.Buffer
	outDone, errDone := readAll(outR, &stdout), readAll(errR, &stderr)
	if err == nil {
		err = cmd.Wait()
	}
	whole := drained(ctx, outDone) && drained(ctx, errDone)
	closeAll(outR, errR) // ends a read that ctx cut short
	<-outDone
	<-errDone
	run := howEnded(ctx, cmd.ProcessState, err)
	if !whole {
		run = iface.GhResult{Exit: -1, CutShort: true}
	}
	run.Stdout, run.Stderr = stdout.Bytes(), stderr.Bytes()
	return run
}

// readAll copies f into b in the background until f ends or is closed, and closes the channel it
// gives when the copy stops.
func readAll(f *os.File, b *bytes.Buffer) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(b, f) // its one error is the close that cuts a run short
	}()
	return done
}

// drained waits for done, the end of one read, and reports false when ctx ends first.
func drained(ctx context.Context, done <-chan struct{}) bool {
	select {
	case <-done:
		return true
	case <-ctx.Done():
	}
	select {
	case <-done:
		return true
	default:
		return false
	}
}

// closeAll closes each pipe end in files. A pipe's close fails only on a file already closed, which
// none here is, so its error is dropped.
func closeAll(files ...*os.File) {
	for _, f := range files {
		_ = f.Close()
	}
}

// howEnded says how a run ended: from state when gh started, else from err, the error the start
// returned. A run whose ctx has ended is cut short when SIGKILL ended gh, the kill CommandContext
// sends, or when gh never started. A gh that exited on its own as ctx ended keeps its exit code.
func howEnded(ctx context.Context, state *os.ProcessState, err error) iface.GhResult {
	run := iface.GhResult{Exit: -1}
	if state == nil {
		if ctx.Err() != nil {
			run.CutShort = true
		} else {
			run.NoStart = err
		}
		return run
	}
	status, ok := state.Sys().(syscall.WaitStatus)
	switch {
	case !ok || !status.Signaled():
		run.Exit = state.ExitCode()
	case status.Signal() == syscall.SIGKILL && ctx.Err() != nil:
		run.CutShort = true
	default:
		run.Signal = int(status.Signal())
	}
	return run
}

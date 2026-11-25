// Package git is the one implementation of iface.Repo. It runs the git program found on PATH, so the
// tests' stub git keeps working.
package git

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"syscall"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// errBound is Run's error for a bound that is not positive.
var errBound = errors.New("git: the bound must be positive")

// Repo reads and changes the repository through git.
type Repo struct{}

var _ iface.Repo = Repo{}

// Run runs git -C call.Dir with call.Args from PATH, with no stdin and call.Env added to the
// process's own environment, and kills git once call.Bound passes. It gives the exit code (minus the
// signal for a git a signal killed) and the bytes git wrote. As report.py's subprocess.run does, it
// reads git's output to its end, even after git exits while a program git started (an ssh, say)
// still holds it, and stops reading at the bound. TimedOut is set when the bound passed before git
// and its output were done. The error is only for a git that could not start, or a bound that is
// not positive.
func (Repo) Run(call iface.GitCall) (iface.GitResult, error) {
	if call.Bound <= 0 {
		return iface.GitResult{}, errBound
	}
	ctx, cancel := context.WithTimeout(context.Background(), call.Bound)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", call.Dir}, call.Args...)...)
	cmd.Env = append(os.Environ(), call.Env...)
	// Pipes of Run's own, not exec's: Wait then returns once git exits, and Run decides how long to
	// read on, where exec's pipes would hold Wait until the output ends.
	outR, outW, err := os.Pipe()
	if err != nil {
		return iface.GitResult{}, err
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		closeAll(outR, outW)
		return iface.GitResult{}, err
	}
	cmd.Stdout, cmd.Stderr = outW, errW
	err = cmd.Start()
	closeAll(outW, errW) // git has its own copies; Run's would keep the pipes from ending
	if err != nil {
		closeAll(outR, errR)
		return iface.GitResult{}, err
	}
	var stdout, stderr bytes.Buffer
	outDone, errDone := readAll(&stdout, outR), readAll(&stderr, errR)
	waitErr := cmd.Wait()
	timedOut := ctx.Err() != nil || !ended(ctx, outDone, errDone)
	closeAll(outR, errR) // ends a read a program git left holding the output past the bound
	<-outDone
	<-errDone
	if cmd.ProcessState == nil {
		return iface.GitResult{}, waitErr
	}
	return iface.GitResult{
		Code:     exitCode(cmd.ProcessState),
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		TimedOut: timedOut,
	}, nil
}

// readAll reads r into buf until r ends or is closed, then closes the channel it gives.
func readAll(buf *bytes.Buffer, r *os.File) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = buf.ReadFrom(r) // a close at the bound ends the read with an error Run does not need
	}()
	return done
}

// ended reports whether every read in dones ended before ctx did.
func ended(ctx context.Context, dones ...<-chan struct{}) bool {
	for _, done := range dones {
		select {
		case <-done:
		case <-ctx.Done():
			return false
		}
	}
	return true
}

// closeAll closes each file, ignoring the errors: each is a pipe end Run no longer needs.
func closeAll(files ...*os.File) {
	for _, f := range files {
		_ = f.Close()
	}
}

// exitCode is the process's exit status, or minus the signal that killed it, as Python's returncode
// gives it. Go's own ExitCode gives -1 for every signal.
func exitCode(state *os.ProcessState) int {
	if status, ok := state.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		return -int(status.Signal())
	}
	return state.ExitCode()
}

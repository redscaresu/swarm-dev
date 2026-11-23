// Package gh starts its program only through exec.Command and exec.CommandContext calls.
package gh

import (
	"context"
	"os"
	"os/exec"
	"syscall"
)

// Run runs gh under ctx.
func Run(ctx context.Context) error {
	return exec.CommandContext(ctx, "gh").Run()
}

// Bash gives the start of a script.
func Bash(script string) *exec.Cmd {
	return exec.Command("bash", script)
}

// Stop signals cmd's process, once Getenv says to.
func Stop(cmd *exec.Cmd) error {
	if os.Getenv("STOP") == "" {
		return nil
	}
	return cmd.Process.Signal(syscall.SIGTERM)
}

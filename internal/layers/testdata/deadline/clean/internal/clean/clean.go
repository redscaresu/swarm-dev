package clean

import (
	"context"
	"os/exec"
	"time"

	"example.com/m/internal/names"
)

// timeout bounds each start.
const timeout = 5 * time.Second

// List starts gh under a deadline made from its caller's context.
func List(parent context.Context) error {
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	return exec.CommandContext(ctx, "gh", "pr", "list").Run()
}

// Wait starts herdr, named by a module constant, under a deadline.
func Wait(at time.Time) error {
	ctx, cancel := context.WithDeadline(context.Background(), at)
	defer cancel()
	return exec.CommandContext(ctx, names.Herdr, "agent", "wait").Run()
}

// Script runs bash with a script path, which needs no deadline.
func Script(path string) error {
	return exec.Command("bash", path, "arg").Run()
}

// Version starts gh on a line that says why it needs no deadline.
func Version() error {
	return exec.Command("gh", "--version").Run() // no-timeout: prints its version and exits
}

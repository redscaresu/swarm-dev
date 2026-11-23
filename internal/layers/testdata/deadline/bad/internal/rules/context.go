package rules

import (
	"context"
	"os/exec"
	"time"
)

// ctx is made with a deadline, but at package level, where no start may take it.
var ctx, _ = context.WithTimeout(context.Background(), time.Second)

// background starts gh under a context with no deadline.
func background() {
	_ = exec.CommandContext(context.Background(), "gh", "pr", "list")
}

// param starts gh under its caller's context.
func param(ctx context.Context) {
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

// withoutCancel drops the deadline of the context it makes.
func withoutCancel() {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_ = exec.CommandContext(context.WithoutCancel(ctx), "gh", "pr", "list")
}

// setAgain sets its context again after WithTimeout.
func setAgain() {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	ctx = context.Background()
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

// shadowed starts gh under an inner context that shadows the one with a deadline.
func shadowed() {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if ctx != nil {
		ctx := context.Background()
		_ = exec.CommandContext(ctx, "gh", "pr", "list")
	}
}

// another makes a context with a deadline, then starts gh under another.
func another() {
	base := context.Background()
	ctx, cancel := context.WithTimeout(base, time.Second)
	defer cancel()
	_, _ = ctx, exec.CommandContext(base, "gh", "pr", "list")
}

// packageLevel starts gh under the package-level context.
func packageLevel() {
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

// inner makes its context in a block the start is not in, so the start takes the package-level one.
func inner() {
	if ctx, cancel := context.WithTimeout(context.Background(), time.Second); ctx != nil {
		defer cancel()
	}
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

// parenSet sets its context again through parentheses.
func parenSet() {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	(ctx) = context.Background()
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

// parenAddress sets its context again through a pointer taken through parentheses.
func parenAddress() {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	*&(ctx) = context.Background()
	_ = exec.CommandContext(ctx, "gh", "pr", "list")
}

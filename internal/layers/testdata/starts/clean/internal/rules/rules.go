// Package rules takes exec.Cmd as a type, which the rule passes.
package rules

import "os/exec"

// zero is an exec.Cmd variable.
var zero exec.Cmd

// Path is c's program.
func Path(c *exec.Cmd) string {
	if c == nil {
		return zero.Path
	}
	return c.Path
}

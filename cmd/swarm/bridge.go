package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
)

// The bridge hands a form of a ported command that is still bash back to bin/swarm.sh. When a
// command's first port leaves one of its forms in bash, that form moves to a dispatch arm named
// _<name>, and the Go runs it as
//
//	bash <SWARMDEV_HOME>/bin/swarm.sh _<name> <args>
//
// with SWARM_PROJECT set to the frame's project, so the nested swarm.sh resolves this project from any
// cwd. Every other variable passes as the binary got it. SWARM_GH_VIA is among them: bin/swarm.sh
// exports it before it runs the binary, so the nested call logs its gh calls under the same via and
// knows it is nested. stdin, stdout and stderr are the call's own, and the exit code is the nested
// call's.
//
// This is the one file of cmd/ that may import os/exec (internal/layers' bridgeFile). It goes when
// the last bash form does.

// envSwarmProject names the project for the nested swarm.sh, as bin/swarm.sh's find_project reads it.
const envSwarmProject = "SWARM_PROJECT"

// bridge runs the bash form _<name> with args and returns its exit code. A frame with no home fails
// with exitUsage, since the script would be a path relative to the cwd. A bash that cannot start, or a
// run a signal ends (it has no exit code), fails as die() does, with exit 1.
func (c *call) bridge(name string, args ...string) int {
	if c.frame.home == "" {
		return c.die(exitUsage, "_"+name+": the frame names no plugin root (SWARMDEV_HOME), so there is no swarm.sh to run")
	}
	script := filepath.Join(c.frame.home, "bin", "swarm.sh")
	cmd := exec.Command("bash", append([]string{script, "_" + name}, args...)...)
	// Of two values for one name in Env, exec uses the last, so the frame's project wins over any
	// SWARM_PROJECT the binary was started with.
	cmd.Env = append(os.Environ(), envSwarmProject+"="+c.frame.project)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = c.stdin, c.stdout, c.stderr
	err := cmd.Run()
	var exitErr *exec.ExitError
	switch {
	case err == nil:
		return 0
	case errors.As(err, &exitErr) && exitErr.ExitCode() >= 0:
		return exitErr.ExitCode()
	}
	return c.die(1, "_"+name+": bash "+script+": "+err.Error())
}

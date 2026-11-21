// The bridge's leave covers os/exec only: syscall still fails.
package main

import (
	"os/exec"
	"syscall"
)

var _, _ = exec.Command, syscall.Getpid

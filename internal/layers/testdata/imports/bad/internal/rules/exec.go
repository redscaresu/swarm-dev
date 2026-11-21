// Package rules imports what a rules package may not.
package rules

import (
	"net"
	"os/exec"
	"syscall"
)

var _, _, _ = net.Dial, exec.Command, syscall.Getpid

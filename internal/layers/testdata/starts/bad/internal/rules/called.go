// Package rules starts processes every way but an exec.Command or exec.CommandContext call.
package rules

import (
	"os"
	"syscall"
)

var _, _ = os.StartProcess("gh", nil, nil) // no-timeout: a comment lets no start through
var _ = syscall.Exec("gh", nil, nil)
var _, _ = syscall.ForkExec("gh", nil, nil)
var _, _, _ = syscall.StartProcess("gh", nil, nil)
var _, _, _ = syscall.Syscall(syscall.SYS_EXECVE, 0, 0, 0)
var _, _, _ = syscall.RawSyscall(syscall.SYS_FORK, 0, 0, 0)

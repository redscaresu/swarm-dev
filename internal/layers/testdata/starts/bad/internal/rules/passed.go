package rules

import (
	"os"
	"os/exec"
	"syscall"
)

var command = exec.Command
var commandContext = exec.CommandContext
var startProcess = os.StartProcess
var forkExec = syscall.ForkExec

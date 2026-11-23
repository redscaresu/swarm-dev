package rules

import (
	"os/exec"
	run "os/exec"
)

var _ = exec.Cmd{}
var _ = &exec.Cmd{Path: "gh"}
var _ = run.Cmd{Path: "herdr"}

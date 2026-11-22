// Command swarm's bridge.go is the one file outside the adapters that may import os/exec.
package main

import "os/exec"

var _ = exec.Command

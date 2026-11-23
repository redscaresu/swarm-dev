package rules

import "os/exec"

// herdr names the program as a module constant.
const herdr = "herdr"

// script is a gh call for a shell's -c.
const script = "gh pr list"

// Each start can wait forever and has no deadline.
func commands() {
	_ = exec.Command("gh", "pr", "list")
	_ = exec.Command("/usr/bin/curl", "-fsS", "https://example.com")
	_ = exec.Command(herdr, "agent", "wait")
	_ = exec.Command("env", "GH_PAGER=", "gh", "pr", "list")
	_ = exec.Command("bash", "-c", "gh pr list")
	_ = exec.Command("/bin/sh", append([]string{"-ec"}, script)...)
}

// variable starts a program the check cannot tell.
func variable(prog string) {
	_ = exec.Command(prog, "pr", "list")
}

// noReason says no-timeout and gives no reason.
func noReason() {
	_ = exec.Command("gh", "auth", "status") // no-timeout:
}

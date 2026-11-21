package main

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"slices"
	"strings"
	"testing"
)

// runMainEnv names the variable that makes TestMain call main() in place of the tests, so a test can
// run this test binary as the command itself.
const runMainEnv = "SWARM_TEST_RUN_MAIN"

func TestMain(m *testing.M) {
	if os.Getenv(runMainEnv) == "1" {
		main()
		// main() must exit; reaching here means it returned.
		os.Exit(99)
	}
	os.Exit(m.Run())
}

// runMain runs the test binary as the command with args, env added to this process's environment
// (its own SWARMDEV_ names dropped) and stdin, and returns its exit code, stdout and stderr.
func runMain(t *testing.T, env []string, stdin string, args ...string) (int, string, string) {
	t.Helper()
	cmd := exec.Command(os.Args[0], args...)
	base := slices.DeleteFunc(os.Environ(), func(kv string) bool { return strings.HasPrefix(kv, "SWARMDEV_") })
	cmd.Env = append(append(base, runMainEnv+"=1"), env...)
	cmd.Stdin = strings.NewReader(stdin)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	var exitErr *exec.ExitError
	switch {
	case err == nil:
		return 0, stdout.String(), stderr.String()
	case errors.As(err, &exitErr):
		return exitErr.ExitCode(), stdout.String(), stderr.String()
	}
	t.Fatalf("running %s: %v", os.Args[0], err)
	return 0, "", ""
}

// If main() drops run()'s code, or writes anything on stdout for a name with no entry, this goes red.
func TestMainExitsWithRunsCode(t *testing.T) {
	code, stdout, stderr := runMain(t, nil, "", "next")
	// Written out here, not taken from main.go, so a change there goes red.
	want := "swarm: the binary has no command 'next'\n"
	if code != 2 || stdout != "" || stderr != want {
		t.Errorf("main() next: code %d, stdout %q, stderr %q; want 2, nothing, %q", code, stdout, stderr, want)
	}
}

// If main() stops reading the frame from its environment, or stops passing stdin and stdout to the
// entry, this goes red.
func TestMainHandsTheFrameToTheEntry(t *testing.T) {
	env := []string{"SWARMDEV_PROJECT=/proj", "SWARMDEV_BOARD=/proj/docs", "SWARMDEV_HOME=/plugin",
		"SWARMDEV_CFG_merge=agent", "SWARMDEV_SRC_merge=config"}
	code, stdout, stderr := runMain(t, env, "in\n", "wrapper-fixture", "a")
	want := "project = /proj\nboard = /proj/docs\nhome = /plugin\narg = a\nstdin = in\nmerge = agent    (config)\n"
	if code != 0 || stdout != want || stderr != "" {
		t.Errorf("main() wrapper-fixture: code %d, stdout %q, stderr %q; want 0, %q, nothing", code, stdout, stderr, want)
	}
}

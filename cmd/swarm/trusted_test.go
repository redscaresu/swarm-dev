package main

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

// writeConfig writes text as a .claude.json in a new folder and returns its path.
func writeConfig(t *testing.T, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), ".claude.json")
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// If the entry stops reading <config> through the store, stops passing <root>, or reads the third
// argument as anything but "git" for a git root, a row's exit code changes and this goes red. Each
// run prints nothing and writes no file, as the Python helper did not.
func TestRequireTrustedDecides(t *testing.T) {
	ancestor := writeConfig(t, `{"projects": {"/w": {"hasTrustDialogAccepted": true}}}`)
	for _, c := range []struct {
		name              string
		root, config, git string
		want              int
	}{
		{"the root itself trusted", "/w", ancestor, "", 0},
		{"the root itself trusted, a git root", "/w", ancestor, "git", 0},
		{"outside git, a trusted ancestor covers it", "/w/sub", ancestor, "", 0},
		{"a git root: its ancestor does not cover it", "/w/sub", ancestor, "git", 1},
		{"only git is a git root", "/w/sub", ancestor, "Git", 0},
		{"no entry for the root", "/x", ancestor, "", 1},
		{"no file: the start goes ahead", "/x", filepath.Join(t.TempDir(), "none"), "", 0},
		{"not JSON: the start goes ahead", "/x", writeConfig(t, `{"projects": {`), "", 0},
		{"projects not an object: refused", "/x", writeConfig(t, `{"projects": []}`), "", 1},
	} {
		got := runFixture(t, handoff("", ""), "", "_require-trusted", c.root, c.config, c.git)
		if got.code != c.want || got.stdout != "" || got.stderr != "" || len(got.writes) != 0 {
			t.Errorf("%s: _require-trusted %s %s %q: code %d, stdout %q, stderr %q, writes %v; want %d and nothing else",
				c.name, c.root, c.config, c.git, got.code, got.stdout, got.stderr, got.writes, c.want)
		}
	}
}

// If the entry runs with a wrong number of arguments (bash calling it wrong, or a by-hand run), it
// must stop in one line with exitUsage rather than guess: dropping the check, or exiting 0 or 1 in its
// place, goes red. The die file takes the line, as die() writes it.
func TestRequireTrustedArgumentCount(t *testing.T) {
	die := filepath.Join(t.TempDir(), "die")
	config := writeConfig(t, `{"projects": {}}`)
	for _, args := range [][]string{{}, {"/w"}, {"/w", config}, {"/w", config, "", "extra"}} {
		got := runFixture(t, handoff(die, ""), "", append([]string{"_require-trusted"}, args...)...)
		// Written out here, not taken from trusted.go, so a change there goes red.
		line := "_require-trusted takes <root> <config> <git|>, and was given " + strconv.Itoa(len(args)) + " argument(s)"
		if got.code != exitUsage || got.stdout != "" || got.stderr != "swarm: "+line+"\n" {
			t.Errorf("_require-trusted %q: code %d, stdout %q, stderr %q; want %d, nothing, %q",
				args, got.code, got.stdout, got.stderr, exitUsage, "swarm: "+line+"\n")
		}
		if b, err := os.ReadFile(die); err != nil || string(b) != line+"\n" {
			t.Errorf("_require-trusted %q: the die file holds %q (%v); want %q", args, b, err, line+"\n")
		}
	}
}

// If the entry loses needsFrame, a run by hand outside bin/swarm.sh decides with no frame: this goes
// red. It also runs main() itself with the real store, so the wiring to it is covered.
func TestRequireTrustedThroughMain(t *testing.T) {
	config := writeConfig(t, `{"projects": {"/w": {"hasTrustDialogAccepted": true}}}`)
	frame := []string{"SWARMDEV_PROJECT=/proj"}
	for _, c := range []struct {
		name   string
		env    []string
		root   string
		code   int
		stderr string
	}{
		{"trusted", frame, "/w", 0, ""},
		{"refused", frame, "/x", 1, ""},
		{"no frame", nil, "/w", exitUsage, "swarm: _require-trusted needs the frame bin/swarm.sh sets up: run it through bin/swarm.sh\n"},
	} {
		code, stdout, stderr := runMain(t, c.env, "", "_require-trusted", c.root, config, "")
		if code != c.code || stdout != "" || stderr != c.stderr {
			t.Errorf("main() _require-trusted, %s: code %d, stdout %q, stderr %q; want %d, nothing, %q",
				c.name, code, stdout, stderr, c.code, c.stderr)
		}
	}
}

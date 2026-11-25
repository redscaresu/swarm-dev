// Package iface holds the four interfaces the rules packages take in place of starting a process or
// touching a file: the agent runner, the code host, the repo and the store. Each has exactly one
// implementation, under internal/adapter/. The store's types sit here beside Store.
//
// Store has the two methods the frame's handoff needs, ReadFile, which _require-trusted reads
// .claude.json with, and the stat, real-path and append methods the board-store ports read and
// write files with. Repo has Run, which report's git runner needs. The other two have none yet: each
// port adds the methods it needs.
package iface

import (
	"io/fs"
	"time"
)

// AgentRunner starts, reads and stops the agents. herdr is its one implementation
// (internal/adapter/herdr).
type AgentRunner interface{}

// CodeHost reads and changes pull requests, checks and merges. gh is its one implementation
// (internal/adapter/gh).
type CodeHost interface{}

// Repo reads and changes the git repository and its worktrees. git is its one implementation
// (internal/adapter/git).
type Repo interface {
	// Run runs git -C call.Dir with call.Args, with no stdin and call.Env added to the process's own
	// environment, and kills it once call.Bound passes. The error is only for a git that could not
	// start, or a Bound that is not positive.
	Run(call GitCall) (GitResult, error)
}

// GitCall is one run of git through Repo.Run.
type GitCall struct {
	Dir   string        // the folder git runs in, passed as git -C <Dir>
	Env   []string      // KEY=value pairs added to the process's own environment; a later one wins
	Bound time.Duration // how long git may run before it is killed; must be positive
	Args  []string      // the arguments after -C <Dir>
}

// GitResult is what one git run gave.
type GitResult struct {
	Code     int    // the exit status, or minus the signal that killed git, as Python's returncode
	Stdout   string // the bytes git wrote to its stdout, unchanged
	Stderr   string // the bytes git wrote to its stderr, unchanged
	TimedOut bool   // the bound passed before git and its output were done; Code and the output are then what it left
}

// Store reads and writes .swarm/, the board's files and the files bin/swarm.sh hands the binary. It
// also reads a file bash names in an argument, such as .claude.json. internal/adapter/store is its one
// implementation.
type Store interface {
	// ReadFile returns all of path's bytes, or the error the read returned.
	ReadFile(path string) ([]byte, error)
	// Stat returns path's file info, following a symlink. Its error wraps fs.ErrNotExist or
	// fs.ErrPermission where the stat failed for that reason.
	Stat(path string) (fs.FileInfo, error)
	// Lstat returns path's file info without following a last symlink. Its error wraps as Stat's does.
	Lstat(path string) (fs.FileInfo, error)
	// RealPath returns the physical path `cd <dir> && pwd -P` prints, failing for a missing path or a file.
	// It does not fail for a folder the caller may not enter, and gives a leading // as one slash.
	RealPath(dir string) (string, error)
	// AppendLine makes path's parent folders as mkdir -p does, then adds line and a newline to the end
	// of path in one write, making the file 0666 before the umask if it is missing.
	AppendLine(path, line string) error
	// WriteLine makes path hold line and a newline, and nothing else.
	WriteLine(path, line string) error
	// AppendLines adds each line, with a newline, to the end of path, making the file if it is missing.
	AppendLines(path string, lines []string) error
}

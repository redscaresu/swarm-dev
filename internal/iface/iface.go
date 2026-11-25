// Package iface holds the four interfaces the rules packages take in place of starting a process or
// touching a file: the agent runner, the code host, the repo and the store. Each has exactly one
// implementation, under internal/adapter/. The store's types sit here beside Store.
//
// Store has the two methods the frame's handoff needs, ReadFile, which _require-trusted reads
// .claude.json with, and the stat, real-path and append methods the board-store ports read and
// write files with. The other three have none yet: each port adds the methods it needs.
// Store's other methods list, write and remove files and make folders, and make a file only where
// none is, remove an empty folder and check a pid, for the ports that need them.
package iface

import "io/fs"

// AgentRunner starts, reads and stops the agents. herdr is its one implementation
// (internal/adapter/herdr).
type AgentRunner interface{}

// CodeHost reads and changes pull requests, checks and merges. gh is its one implementation
// (internal/adapter/gh).
type CodeHost interface{}

// Repo reads and changes the git repository and its worktrees. git is its one implementation
// (internal/adapter/git).
type Repo interface{}

// Store reads and writes .swarm/, the board's files and the files bin/swarm.sh hands the binary. It
// also reads a file bash names in an argument, such as .claude.json, and says whether a lock's
// holder still runs. internal/adapter/store is its one implementation.
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
	// Glob returns the paths under dir that pattern matches, sorted, as Python's
	// glob.glob(os.path.join(glob.escape(dir), pattern)) does: dir is literal, and a pattern level that
	// does not start with a dot matches no dot name. Its one error is filepath.ErrBadPattern, which a
	// pattern with an empty, . or .. level gets too.
	Glob(dir, pattern string) ([]string, error)
	// IsFile reports whether path, its symlinks followed, is a regular file, as os.path.isfile does.
	IsFile(path string) bool
	// MkdirAll makes path and each missing folder above it, as mkdir -p does, returning the os error.
	MkdirAll(path string) error
	// WriteAtomic makes path hold data through a temp file in path's folder renamed over it. When a step
	// fails it removes the temp file, leaves path as it was and returns the os error.
	WriteAtomic(path string, data []byte) error
	// Remove deletes the file or symlink path, never a folder, returning the os error.
	Remove(path string) error
	// CreateExclusive makes path holding data, or fails with an error wrapping fs.ErrExist when
	// path is there, as an open with O_CREAT|O_EXCL does. When the write fails it removes path again.
	CreateExclusive(path string, data []byte) error
	// RemoveDir deletes the folder path when it is empty, never a file, returning the os error.
	RemoveDir(path string) error
	// Alive reports whether process pid runs, one another user owns too; false for a pid of 0 or
	// less, which would name a process group.
	Alive(pid int) bool
	// WriteLine makes path hold line and a newline, and nothing else.
	WriteLine(path, line string) error
	// AppendLines adds each line, with a newline, to the end of path, making the file if it is missing.
	AppendLines(path string, lines []string) error
}

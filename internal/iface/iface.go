// Package iface holds the four interfaces the rules packages take in place of starting a process or
// touching a file: the agent runner, the code host, the repo and the store. Each has exactly one
// implementation, under internal/adapter/. The store's types sit here beside Store.
//
// Store has the two methods the frame's handoff needs, and the other three have none yet: each port
// adds the methods it needs.
package iface

// AgentRunner starts, reads and stops the agents. herdr is its one implementation
// (internal/adapter/herdr).
type AgentRunner interface{}

// CodeHost reads and changes pull requests, checks and merges. gh is its one implementation
// (internal/adapter/gh).
type CodeHost interface{}

// Repo reads and changes the git repository and its worktrees. git is its one implementation
// (internal/adapter/git).
type Repo interface{}

// Store reads and writes .swarm/, the board's files and the files bin/swarm.sh hands the binary.
// internal/adapter/store is its one implementation.
type Store interface {
	// WriteLine makes path hold line and a newline, and nothing else.
	WriteLine(path, line string) error
	// AppendLines adds each line, with a newline, to the end of path, making the file if it is missing.
	AppendLines(path string, lines []string) error
}

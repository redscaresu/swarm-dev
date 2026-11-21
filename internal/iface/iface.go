// Package iface holds the four interfaces the rules packages take in place of starting a process or
// touching a file: the agent runner, the code host, the repo and the store. Each has exactly one
// implementation, under internal/adapter/. The store's types sit here beside Store.
//
// Each interface has no methods yet: each port adds the methods it needs.
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

// Store reads and writes .swarm/ and the board's files. internal/adapter/store is its one
// implementation.
type Store interface{}

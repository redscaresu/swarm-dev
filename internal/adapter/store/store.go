// Package store is the one implementation of iface.Store: the files under .swarm/ and the board's
// files. It reads and writes them itself and runs no program.
package store

import "github.com/redscaresu/swarm-dev/internal/iface"

// Files reads and writes .swarm/ and the board's files.
type Files struct{}

var _ iface.Store = Files{}

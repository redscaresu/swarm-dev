// Package gh is the one implementation of iface.CodeHost. It runs the gh program found on PATH, so
// the tests' stub gh and the agents' gh shim keep working.
package gh

import "github.com/redscaresu/swarm-dev/internal/iface"

// Host reads and changes the code host through gh.
type Host struct{}

var _ iface.CodeHost = Host{}

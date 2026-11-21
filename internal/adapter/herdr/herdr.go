// Package herdr is the one implementation of iface.AgentRunner. It runs the herdr program found on
// PATH, so the tests' stub herdr keeps working.
package herdr

import "github.com/redscaresu/swarm-dev/internal/iface"

// Runner runs the agents through herdr.
type Runner struct{}

var _ iface.AgentRunner = Runner{}
